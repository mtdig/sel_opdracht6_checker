package domain;

import java.time.Duration;
import java.time.Instant;
import java.util.*;
import java.util.concurrent.*;
import java.util.function.Consumer;


public class DomainController {

    private final List<CheckState> checkStates;
    private final Map<String, CheckState> checkIndex;
    private CheckContext context;
    private Duration totalDuration = Duration.ZERO;

    // callback for state change notifications (called on background thread)
    private Consumer<CheckState> onCheckStateChanged;

    // callback when all checks are done
    private Runnable onAllDone;

    // callback when a single check finishes (used by detail dialog)
    private Consumer<CheckState> onSingleDone;

    public DomainController() {
        List<Check> checks = CheckRegistry.allChecks();
        checkStates = new ArrayList<>();
        checkIndex = new LinkedHashMap<>();
        for (Check c : checks) {
            CheckState state = new CheckState(c);
            checkStates.add(state);
            checkIndex.put(c.getId(), state);
        }
    }


    public void configure(String target, String localUser, Map<String, String> secrets) {
        this.context = new CheckContext(target, localUser, secrets);
    }

    public boolean isConfigured() {
        return context != null;
    }


    public Consumer<CheckState> getOnCheckStateChanged() {
        return onCheckStateChanged;
    }

    public void setOnCheckStateChanged(Consumer<CheckState> listener) {
        this.onCheckStateChanged = listener;
    }

    public void setOnAllDone(Runnable listener) {
        this.onAllDone = listener;
    }

    public Consumer<CheckState> getOnSingleDone() {
        return onSingleDone;
    }

    public void setOnSingleDone(Consumer<CheckState> listener) {
        this.onSingleDone = listener;
    }


    public List<CheckState> getCheckStates() {
        return Collections.unmodifiableList(checkStates);
    }

    public CheckState getCheckState(String id) {
        return checkIndex.get(id);
    }


    public List<String> getSections() {
        LinkedHashSet<String> sections = new LinkedHashSet<>();
        for (CheckState cs : checkStates) {
            sections.add(cs.getSection());
        }
        return new ArrayList<>(sections);
    }


    public List<CheckState> getChecksBySection(String section) {
        return checkStates.stream()
                .filter(cs -> cs.getSection().equals(section))
                .toList();
    }

    public Duration getTotalDuration() {
        return totalDuration;
    }

    public int countPassed() {
        return (int) checkStates.stream()
                .flatMap(cs -> cs.getResults().stream())
                .filter(r -> r.status() == CheckStatus.PASS).count();
    }

    public int countFailed() {
        return (int) checkStates.stream()
                .flatMap(cs -> cs.getResults().stream())
                .filter(r -> r.status() == CheckStatus.FAIL).count();
    }

    public int countSkipped() {
        return (int) checkStates.stream()
                .flatMap(cs -> cs.getResults().stream())
                .filter(r -> r.status() == CheckStatus.SKIP).count();
    }

    public int countTotal() {
        return (int) checkStates.stream()
                .mapToLong(cs -> cs.getResults().size())
                .sum();
    }

 
    public void resetAll() {
        for (CheckState cs : checkStates) {
            cs.setStatus(CheckStatus.NOT_RUN);
            cs.setDuration(Duration.ZERO);
            cs.setResults(List.of());
        }
        totalDuration = Duration.ZERO;
    }


    public void runAll() {
        if (context == null) throw new CheckException("Not configured");
        resetAll();

        ExecutorService executor = Executors.newFixedThreadPool(
                Math.min(checkStates.size(), 8));

        Thread scheduler = new Thread(() -> {
            Instant totalStart = Instant.now();
            Set<String> done = ConcurrentHashMap.newKeySet();
            Set<String> launched = ConcurrentHashMap.newKeySet();
            CountDownLatch allLatch = new CountDownLatch(checkStates.size());

            Runnable scheduleReady = () -> {
                for (CheckState cs : checkStates) {
                    String id = cs.getId();
                    if (launched.contains(id)) continue;
                    if (!depsReady(cs.getCheck().getDependencies(), done)) continue;
                    launched.add(id);
                    executor.submit(() -> {
                        executeCheck(cs);
                        done.add(id);
                        allLatch.countDown();
                        // after each completion, try to schedule more
                        synchronized (done) {
                            done.notifyAll();
                        }
                    });
                }
            };

            // start
            scheduleReady.run();

            // wait loop
            while (done.size() < checkStates.size()) {
                synchronized (done) {
                    try {
                        done.wait(200);
                    } catch (InterruptedException e) {
                        Thread.currentThread().interrupt();
                        break;
                    }
                }
                scheduleReady.run();
            }

            try {
                allLatch.await();
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }

            totalDuration = Duration.between(totalStart, Instant.now());
            executor.shutdown();

            if (onAllDone != null) {
                onAllDone.run();
            }
        }, "check-scheduler");
        scheduler.setDaemon(true);
        scheduler.start();
    }


    public void runSingle(CheckState cs) {
        if (context == null) throw new CheckException("Not configured");
        // keep previous results visible while running — they'll be replaced when done
        cs.setStatus(CheckStatus.RUNNING);
        cs.setDuration(Duration.ZERO);
        notifyChanged(cs);

        Thread t = new Thread(() -> {
            Instant start = Instant.now();
            List<CheckResult> results;
            try {
                results = cs.getCheck().run(context);
            } catch (CheckException e) {
                results = List.of(CheckResult.fail(cs.getName(), "Unexpected error: " + e.getMessage()));
            }
            Duration elapsed = Duration.between(start, Instant.now());

            cs.setResults(results);
            cs.setDuration(elapsed);
            cs.setStatus(cs.deriveOverallStatus());
            notifyChanged(cs);

            if (onSingleDone != null) {
                onSingleDone.accept(cs);
            }
        }, "check-single-" + cs.getId());
        t.setDaemon(true);
        t.start();
    }


    private void executeCheck(CheckState cs) {
        cs.setStatus(CheckStatus.RUNNING);
        notifyChanged(cs);

        Instant start = Instant.now();
        List<CheckResult> results;
        try {
            results = cs.getCheck().run(context);
        } catch (CheckException e) {
            results = List.of(CheckResult.fail(cs.getName(), "Unexpected error: " + e.getMessage()));
        }
        Duration elapsed = Duration.between(start, Instant.now());

        cs.setResults(results);
        cs.setDuration(elapsed);
        cs.setStatus(cs.deriveOverallStatus());
        notifyChanged(cs);
    }

    private boolean depsReady(List<String> deps, Set<String> done) {
        for (String dep : deps) {
            if (!done.contains(dep)) return false;
        }
        return true;
    }

    private void notifyChanged(CheckState cs) {
        if (onCheckStateChanged != null) {
            onCheckStateChanged.accept(cs);
        }
    }


    public void close() {
        if (context != null) context.close();
    }
}
