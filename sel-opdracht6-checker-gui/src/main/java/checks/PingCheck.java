package checks;

import domain.Check;
import domain.CheckContext;
import domain.CheckResult;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

public class PingCheck implements Check {

    @Override public String getId() { return "ping"; }
    @Override public String getName() { return "VM reachable via ICMP ping"; }
    @Override public String getSection() { return "Network"; }
    @Override public String getProtocol() { return "ICMP"; }
    @Override public String getPort() { return "-"; }

    @Override
    public List<CheckResult> run(CheckContext ctx) {
        try {
            // Use system ping command — InetAddress.isReachable() needs root for ICMP
            ProcessBuilder pb = new ProcessBuilder(buildPingCommand(ctx.getTarget()));
            pb.redirectErrorStream(true);
            Process proc = pb.start();
            int exitCode = proc.waitFor();
            String output = new String(proc.getInputStream().readAllBytes()).trim();

            if (exitCode == 0) {
                // Extract round-trip time if available
                String rtt = "";
                for (String line : output.split("\n")) {
                    if (line.contains("rtt") || line.contains("round-trip")) {
                        rtt = " (" + line.trim() + ")";
                        break;
                    }
                }
                return List.of(CheckResult.pass("VM is reachable at " + ctx.getTarget() + " (ping)" + rtt));
            }
            return List.of(CheckResult.fail(
                    "VM is not reachable at " + ctx.getTarget(),
                    "Ping failed - 0 packets received"));
        } catch (java.io.IOException | InterruptedException e) {
            return List.of(CheckResult.fail(
                    "VM is not reachable at " + ctx.getTarget(),
                    "Ping error: " + e.getMessage()));
        }
    }

    static List<String> buildPingCommand(String target) {
        List<String> command = new ArrayList<>();
        command.add("ping");

        String os = System.getProperty("os.name", "").toLowerCase(Locale.ROOT);
        if (os.contains("win")) {
            command.add("-n");
            command.add("1");
            command.add("-w");
            command.add("5000"); // milliseconds
        } else {
            command.add("-c");
            command.add("1");
            command.add("-W");
            command.add("5"); // seconds
        }

        command.add(target);
        return command;
    }
}
