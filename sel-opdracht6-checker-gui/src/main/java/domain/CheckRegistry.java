package domain;

import checks.*;

import java.util.List;


public final class CheckRegistry {

    private CheckRegistry() {
    }

    public static List<Check> allChecks() {
        return List.of(
                // no dependencies - run in parallel
                new PingCheck(),
                new SSHCheck(),
                new ApacheCheck(),
                new WordPressReachableCheck(),
                new WordPressPostsCheck(),
                new WordPressLoginCheck(),
                new PortainerCheck(),
                new VaultwardenCheck(),
                new PlankaCheck(),
                // depend on SSH
                new InternetCheck(),
                new SFTPCheck(),
                new MySQLRemoteCheck(),
                new MySQLLocalCheck(),
                new MySQLAdminCheck(),
                new WordPressDBCheck(),
                new MinetestCheck(),
                new DockerCheck()
        );
    }
}
