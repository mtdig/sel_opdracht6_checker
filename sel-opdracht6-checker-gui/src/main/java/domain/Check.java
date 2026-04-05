package domain;

import java.time.Duration;
import java.util.List;


public interface Check {

    String getId();

    String getName();

    String getSection();

    String getProtocol();

    String getPort();

    default List<String> getDependencies() {
        return List.of();
    }

    /**
     * Execute the check and return one or more results.
     *
     * @param ctx the shared runtime context (target, SSH session, secrets)
     * @return list of check results
     */
    List<CheckResult> run(CheckContext ctx);
}
