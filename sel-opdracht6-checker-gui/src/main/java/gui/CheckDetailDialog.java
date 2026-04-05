package gui;

import domain.*;
import javafx.application.Platform;
import javafx.geometry.Insets;
import javafx.geometry.Pos;
import javafx.scene.control.*;
import javafx.scene.layout.*;
import javafx.stage.Modality;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.function.Consumer;


public class CheckDetailDialog extends Dialog<Void> {

    private final DomainController dc;
    private final String section;
    private VBox contentBox;
    private final Map<String, VBox> cardLookup = new HashMap<>();

    private Consumer<CheckState> previousOnChanged;
    private Consumer<CheckState> previousOnSingleDone;

    public CheckDetailDialog(DomainController dc, String section) {
        this.dc = dc;
        this.section = section;

        setTitle(section + " \u2014 Check Details");
        initModality(Modality.APPLICATION_MODAL);
        setResizable(true);

        buildContent();
        installCallbacks();

        getDialogPane().getButtonTypes().add(ButtonType.CLOSE);

        getDialogPane().setPrefSize(640, 540);

        setOnHidden(e -> restoreCallbacks());
    }


    private void installCallbacks() {
        previousOnChanged = null; // can't read, but we chain
        Consumer<CheckState> outerChanged = dc.getOnCheckStateChanged();
        previousOnChanged = outerChanged;
        dc.setOnCheckStateChanged(cs -> {
            Platform.runLater(() -> updateCard(cs));
            if (previousOnChanged != null) previousOnChanged.accept(cs);
        });

        Consumer<CheckState> outerSingle = dc.getOnSingleDone();
        previousOnSingleDone = outerSingle;
        dc.setOnSingleDone(cs -> {
            Platform.runLater(() -> updateCard(cs));
            if (previousOnSingleDone != null) previousOnSingleDone.accept(cs);
        });
    }

    private void restoreCallbacks() {
        dc.setOnCheckStateChanged(previousOnChanged);
        dc.setOnSingleDone(previousOnSingleDone);
    }

    private void buildContent() {
        contentBox = new VBox(12);
        contentBox.setPadding(new Insets(12));

        rebuildChecks();

        ScrollPane scrollPane = new ScrollPane(contentBox);
        scrollPane.setFitToWidth(true);

        getDialogPane().setContent(scrollPane);
    }

    private void rebuildChecks() {
        contentBox.getChildren().clear();
        cardLookup.clear();

        Label header = new Label(section);
        header.getStyleClass().add("dialog-header");
        contentBox.getChildren().add(header);

        List<CheckState> checks = dc.getChecksBySection(section);
        for (CheckState cs : checks) {
            VBox card = buildCheckCard(cs);
            cardLookup.put(cs.getId(), card);
            contentBox.getChildren().add(card);
        }
    }


    private void updateCard(CheckState cs) {
        VBox existing = cardLookup.get(cs.getId());
        if (existing == null) return;
        int idx = contentBox.getChildren().indexOf(existing);
        if (idx < 0) return;

        VBox newCard = buildCheckCard(cs);
        cardLookup.put(cs.getId(), newCard);
        contentBox.getChildren().set(idx, newCard);
    }

    private VBox buildCheckCard(CheckState cs) {
        VBox card = new VBox(6);
        card.setPadding(new Insets(10));
        card.getStyleClass().addAll("check-card", cardStatusClass(cs.getStatus()));

        Label nameLbl = new Label(cs.getName());
        nameLbl.getStyleClass().add("card-name");

        Label statusBadge = new Label(cs.getStatus().name());
        statusBadge.getStyleClass().addAll("badge", badgeStatusClass(cs.getStatus()));
        statusBadge.setPadding(new Insets(2, 8, 2, 8));

        Region spacer = new Region();
        HBox.setHgrow(spacer, Priority.ALWAYS);
        HBox row1 = new HBox(8, nameLbl, spacer, statusBadge);
        row1.setAlignment(Pos.CENTER_LEFT);

        String meta = String.format("ID: %s  |  Protocol: %s  |  Port: %s",
                cs.getId(), cs.getProtocol(), cs.getPort());
        if (cs.getDuration() != null && cs.getDuration().toMillis() > 0) {
            meta += String.format("  |  Duration: %.1fs", cs.getDuration().toMillis() / 1000.0);
        }
        Label metaLbl = new Label(meta);
        metaLbl.getStyleClass().add("card-meta");

        card.getChildren().addAll(row1, metaLbl);

        if (cs.getStatus() == CheckStatus.RUNNING) {
            ProgressBar bar = new ProgressBar();
            bar.setProgress(ProgressBar.INDETERMINATE_PROGRESS);
            bar.setMaxWidth(Double.MAX_VALUE);
            bar.setPrefHeight(6);
            bar.getStyleClass().add("running-bar");
            card.getChildren().add(bar);
        }

        boolean isRunning = cs.getStatus() == CheckStatus.RUNNING;
        if (!cs.getResults().isEmpty()) {
            Separator sep = new Separator();
            sep.getStyleClass().add("card-separator");
            card.getChildren().add(sep);

            if (isRunning) {
                Label retestHint = new Label("Re-running tests\u2026");
                retestHint.getStyleClass().add("retest-hint");
                card.getChildren().add(retestHint);
            }

            for (CheckResult r : cs.getResults()) {
                HBox resultRow = new HBox(8);
                resultRow.setAlignment(Pos.CENTER_LEFT);
                resultRow.getStyleClass().add("result-row");

                if (isRunning) {
                    // grey out previous results while retesting
                    Label icon = new Label("\u23F3 \u2026");
                    icon.getStyleClass().addAll("result-icon", "result-retesting");
                    icon.setMinWidth(50);

                    Label msg = new Label(r.message());
                    msg.getStyleClass().addAll("card-result-msg", "result-retesting");
                    msg.setWrapText(true);
                    HBox.setHgrow(msg, Priority.ALWAYS);

                    resultRow.getChildren().addAll(icon, msg);
                } else {
                    Label icon = new Label(resultIcon(r.status()));
                    icon.getStyleClass().addAll("result-icon", resultColorClass(r.status()));
                    icon.setMinWidth(50);

                    Label msg = new Label(r.message());
                    msg.getStyleClass().add("card-result-msg");
                    msg.setWrapText(true);
                    HBox.setHgrow(msg, Priority.ALWAYS);

                    resultRow.getChildren().addAll(icon, msg);
                }
                card.getChildren().add(resultRow);

                if (!isRunning && r.detail() != null && !r.detail().isEmpty()) {
                    Label detail = new Label("\u2514\u2500 " + r.detail());
                    detail.getStyleClass().add("card-result-detail");
                    detail.setWrapText(true);
                    detail.setPadding(new Insets(0, 0, 0, 58));
                    card.getChildren().add(detail);
                }
            }
        }

        Button runBtn = new Button(cs.getStatus() == CheckStatus.RUNNING ? "Running\u2026" : "\u25B6 Run");
        runBtn.getStyleClass().add("btn-small");
        runBtn.setDisable(cs.getStatus() == CheckStatus.RUNNING);
        runBtn.setOnAction(e -> {
            if (!dc.isConfigured()) return;
            runBtn.setDisable(true);
            runBtn.setText("Running\u2026");

            dc.runSingle(cs);

        });

        HBox btnRow = new HBox(runBtn);
        btnRow.setAlignment(Pos.CENTER_RIGHT);
        btnRow.setPadding(new Insets(4, 0, 0, 0));
        card.getChildren().add(btnRow);

        return card;
    }


    private String cardStatusClass(CheckStatus status) {
        return switch (status) {
            case NOT_RUN -> "card-not-run";
            case RUNNING -> "card-running";
            case PASS    -> "card-pass";
            case FAIL    -> "card-fail";
            case SKIP    -> "card-skip";
        };
    }

    private String badgeStatusClass(CheckStatus status) {
        return switch (status) {
            case NOT_RUN -> "badge-not-run";
            case RUNNING -> "badge-running";
            case PASS    -> "badge-pass";
            case FAIL    -> "badge-fail";
            case SKIP    -> "badge-skip";
        };
    }

    private String resultColorClass(CheckStatus status) {
        return switch (status) {
            case PASS -> "result-pass";
            case FAIL -> "result-fail";
            case SKIP -> "result-skip";
            default -> "";
        };
    }

    private String resultIcon(CheckStatus status) {
        return switch (status) {
            case PASS -> "\u2705 PASS";
            case FAIL -> "\u274C FAIL";
            case SKIP -> "\u26A0 SKIP";
            default -> "  \u2014\u2014  ";
        };
    }
}
