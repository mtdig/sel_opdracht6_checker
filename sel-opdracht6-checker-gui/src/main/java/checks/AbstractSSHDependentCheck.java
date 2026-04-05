package checks;

import domain.Check;
import domain.CheckContext;
import domain.CheckResult;

import java.util.List;


public abstract class AbstractSSHDependentCheck implements Check {

    @Override
    public List<String> getDependencies() {
        return List.of("ssh");
    }

    protected List<CheckResult> requireSsh(CheckContext ctx, String name) {
        if (!ctx.isSshOk()) {
            return List.of(CheckResult.skip(name, "SSH connection not available"));
        }
        return null; // null means SSH is OK
    }
}
