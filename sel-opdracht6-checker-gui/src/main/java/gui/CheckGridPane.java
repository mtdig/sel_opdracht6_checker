package gui;

import domain.CheckState;
import domain.CheckStatus;
import domain.DomainController;
import javafx.geometry.Pos;
import javafx.scene.control.Label;
import javafx.scene.layout.*;

import java.util.HashMap;
import java.util.List;
import java.util.Map;


public class CheckGridPane extends FlowPane {

    private final DomainController dc;
    private final Map<String, VBox> tileLookup = new HashMap<>();

    public CheckGridPane(DomainController dc) {
        this.dc = dc;
        getStyleClass().add("check-grid");
        setAlignment(Pos.TOP_LEFT);
        buildTiles();
    }

    private void buildTiles() {
        for (String section : dc.getSections()) {
            VBox tile = createTile(section);
            tileLookup.put(section, tile);
            getChildren().add(tile);
        }
    }

    private VBox createTile(String section) {
        List<CheckState> checks = dc.getChecksBySection(section);

        Label titleLabel = new Label(section);
        titleLabel.getStyleClass().add("tile-title");

        Label countLabel = new Label(checks.size() + (checks.size() == 1 ? " check" : " checks"));
        countLabel.getStyleClass().add("tile-count");

        Label statusLabel = new Label(statusSummary(checks));
        statusLabel.getStyleClass().add("tile-status");

        VBox tile = new VBox(6, titleLabel, countLabel, statusLabel);
        tile.getStyleClass().addAll("tile", tileStatusClass(aggregateStatus(checks)));

        tile.setOnMouseClicked(e -> {
            CheckDetailDialog dialog = new CheckDetailDialog(dc, section);
            dialog.showAndWait();
            updateSection(section);
        });

        return tile;
    }

    void updateSection(String section) {
        VBox tile = tileLookup.get(section);
        if (tile == null) return;
        List<CheckState> checks = dc.getChecksBySection(section);

        if (tile.getChildren().size() >= 3 && tile.getChildren().get(2) instanceof Label statusLbl) {
            statusLbl.setText(statusSummary(checks));
        }

        tile.getStyleClass().removeAll("tile-not-run", "tile-running", "tile-pass", "tile-fail", "tile-skip");
        tile.getStyleClass().add(tileStatusClass(aggregateStatus(checks)));
    }

    void updateAll() {
        for (String section : dc.getSections()) {
            updateSection(section);
        }
    }

    private CheckStatus aggregateStatus(List<CheckState> checks) {
        boolean anyRunning = false;
        boolean anyFail = false;
        boolean anyPass = false;
        boolean anySkip = false;
        boolean allNotRun = true;

        for (CheckState cs : checks) {
            switch (cs.getStatus()) {
                case RUNNING -> { anyRunning = true; allNotRun = false; }
                case FAIL    -> { anyFail = true; allNotRun = false; }
                case PASS    -> { anyPass = true; allNotRun = false; }
                case SKIP    -> { anySkip = true; allNotRun = false; }
                default -> {}
            }
        }

        if (allNotRun) return CheckStatus.NOT_RUN;
        if (anyRunning) return CheckStatus.RUNNING;
        if (anyFail) return CheckStatus.FAIL;
        if (anySkip && !anyPass) return CheckStatus.SKIP;
        return CheckStatus.PASS;
    }

    private String statusSummary(List<CheckState> checks) {
        long pass = checks.stream().filter(c -> c.getStatus() == CheckStatus.PASS).count();
        long fail = checks.stream().filter(c -> c.getStatus() == CheckStatus.FAIL).count();
        long skip = checks.stream().filter(c -> c.getStatus() == CheckStatus.SKIP).count();
        long running = checks.stream().filter(c -> c.getStatus() == CheckStatus.RUNNING).count();
        long notRun = checks.stream().filter(c -> c.getStatus() == CheckStatus.NOT_RUN).count();

        if (notRun == checks.size()) return "Not yet run";

        StringBuilder sb = new StringBuilder();
        if (pass > 0) sb.append(pass).append(" passed ");
        if (fail > 0) sb.append(fail).append(" failed ");
        if (skip > 0) sb.append(skip).append(" skipped ");
        if (running > 0) sb.append(running).append(" running ");
        return sb.toString().trim();
    }

    private String tileStatusClass(CheckStatus status) {
        return switch (status) {
            case NOT_RUN -> "tile-not-run";
            case RUNNING -> "tile-running";
            case PASS    -> "tile-pass";
            case FAIL    -> "tile-fail";
            case SKIP    -> "tile-skip";
        };
    }
}
