package domain;


public enum CheckStatus {
    NOT_RUN,
    RUNNING,
    PASS,
    FAIL,
    SKIP;

    public boolean isTerminal() {
        return this == PASS || this == FAIL || this == SKIP;
    }
}
