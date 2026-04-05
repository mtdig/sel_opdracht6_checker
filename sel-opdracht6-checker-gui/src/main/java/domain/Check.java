package domain;

import java.time.Duration;
import java.util.List;

/**
 * Interface for all check implementations.
 */
public interface Check {

    /** Unique machine identifier, e.g. "ping", "ssh", "apache". */
    String getId();

    /** Human-readable name shown in the UI. */
    String getName();

    /** Logical section/group, e.g. "Network", "SSH", "WordPress". */
    String getSection();

    /** Protocol tested: ICMP, TCP/SSH, HTTPS, HTTP, TCP, UDP, SFTP. */
    String getProtocol();

    /** Port tested, e.g. "22", "443", "-" for ICMP. */
    String getPort();

    /** IDs of checks that must complete before this one can run. */
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
