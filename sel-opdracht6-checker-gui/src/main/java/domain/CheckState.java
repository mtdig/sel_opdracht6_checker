package domain;

import java.time.Duration;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;


public class CheckState {

    private final Check check;
    private CheckStatus status = CheckStatus.NOT_RUN;
    private Duration duration = Duration.ZERO;
    private List<CheckResult> results = new ArrayList<>();

    public CheckState(Check check) {
        this.check = check;
    }


    public Check getCheck() {
        return check;
    }

    public String getId() {
        return check.getId();
    }

    public String getName() {
        return check.getName();
    }

    public String getSection() {
        return check.getSection();
    }

    public String getProtocol() {
        return check.getProtocol();
    }

    public String getPort() {
        return check.getPort();
    }

    public CheckStatus getStatus() {
        return status;
    }

    public void setStatus(CheckStatus status) {
        this.status = status;
    }

    public Duration getDuration() {
        return duration;
    }

    public void setDuration(Duration duration) {
        this.duration = duration;
    }

    public List<CheckResult> getResults() {
        return Collections.unmodifiableList(results);
    }

    public void setResults(List<CheckResult> results) {
        this.results = new ArrayList<>(results);
    }


    public CheckStatus deriveOverallStatus() {
        if (results.isEmpty()) return CheckStatus.NOT_RUN;
        boolean hasFail = results.stream().anyMatch(r -> r.status() == CheckStatus.FAIL);
        if (hasFail) return CheckStatus.FAIL;
        boolean allSkip = results.stream().allMatch(r -> r.status() == CheckStatus.SKIP);
        if (allSkip) return CheckStatus.SKIP;
        return CheckStatus.PASS;
    }
}
