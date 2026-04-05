package domain;


public record CheckResult(CheckStatus status, String message, String detail) {

    public static CheckResult pass(String message) {
        return new CheckResult(CheckStatus.PASS, message, "");
    }

    public static CheckResult fail(String message, String detail) {
        return new CheckResult(CheckStatus.FAIL, message, detail);
    }

    public static CheckResult skip(String message, String reason) {
        return new CheckResult(CheckStatus.SKIP, message, reason);
    }
}
