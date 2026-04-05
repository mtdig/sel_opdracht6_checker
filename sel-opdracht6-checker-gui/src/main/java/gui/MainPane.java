package gui;

import domain.CheckState;
import domain.CheckStatus;
import domain.DomainController;
import javafx.application.Platform;
import javafx.geometry.Pos;
import javafx.scene.control.*;
import javafx.scene.layout.*;


public class MainPane extends BorderPane {

    private final DomainController dc;
    private CheckGridPane gridPane;
    private SidePanel sidePanel;
    private Label statusLabel;

    public MainPane(DomainController dc) {
        this.dc = dc;
        buildUI();
        wireCallbacks();
    }

    private void buildUI() {
        setTop(buildMenuBar());

        sidePanel = new SidePanel(dc, this);
        setLeft(sidePanel);

        gridPane = new CheckGridPane(dc);
        ScrollPane scrollPane = new ScrollPane(gridPane);
        scrollPane.setFitToWidth(true);
        setCenter(scrollPane);

        statusLabel = new Label("Ready");
        statusLabel.getStyleClass().add("status-label");
        statusLabel.setMaxWidth(Double.MAX_VALUE);
        HBox statusBar = new HBox(statusLabel);
        HBox.setHgrow(statusLabel, Priority.ALWAYS);
        statusBar.getStyleClass().add("status-bar");
        setBottom(statusBar);
    }

    private MenuBar buildMenuBar() {
        MenuItem exitItem = new MenuItem("Exit");
        exitItem.setOnAction(e -> {
            dc.close();
            Platform.exit();
        });
        Menu fileMenu = new Menu("File");
        fileMenu.getItems().add(exitItem);

        MenuItem aboutItem = new MenuItem("About");
        aboutItem.setOnAction(e -> showAbout());
        Menu helpMenu = new Menu("Help");
        helpMenu.getItems().add(aboutItem);

        return new MenuBar(fileMenu, helpMenu);
    }

    private void showAbout() {
        Alert alert = new Alert(Alert.AlertType.INFORMATION);
        alert.setTitle("About");
        alert.setHeaderText("SELab Opdracht 6 Checker");
        alert.setContentText(
                "JavaFX GUI for checking Opdracht6 configuration.\n\n"
                + "Checks network, SSH, Apache, WordPress, MySQL,\n"
                + "Portainer, Vaultwarden, Planka, SFTP, Minetest, and Docker.\n\n"
                + "Built with Java 21 + JavaFX + Apache MINA SSHD.");
        alert.showAndWait();
    }

    private void wireCallbacks() {
        dc.setOnCheckStateChanged(cs -> Platform.runLater(() -> {
            gridPane.updateSection(cs.getSection());
            updateStatus();
        }));

        dc.setOnAllDone(() -> Platform.runLater(() -> {
            gridPane.updateAll();
            updateStatus();
            sidePanel.setRunning(false);
            showSummary();
        }));
    }

    private void showSummary() {
        int pass = dc.countPassed();
        int fail = dc.countFailed();
        int skip = dc.countSkipped();
        int total = dc.countTotal();
        long ms = dc.getTotalDuration().toMillis();

        Dialog<Void> dialog = new Dialog<>();
        dialog.setTitle("Run Complete");
        dialog.initModality(javafx.stage.Modality.APPLICATION_MODAL);
        dialog.setResizable(true);

        VBox box = new VBox(0);
        box.getStyleClass().add("summary-pane");

        VBox headerBox = new VBox(12);
        headerBox.getStyleClass().add("summary-header-box");

        Label title = new Label(fail == 0 ? "\u2705 All Checks Passed!" : "\u26A0 Run Complete");
        title.getStyleClass().add(fail == 0 ? "summary-title-pass" : "summary-title-fail");

        HBox stats = new HBox(16);
        stats.setAlignment(Pos.CENTER);
        stats.getChildren().addAll(
                statPill(String.valueOf(pass), "PASSED", "pass"),
                statPill(String.valueOf(fail), "FAILED", "fail"),
                statPill(String.valueOf(skip), "SKIPPED", "skip"));

        Label totalLbl = new Label(String.format("%d total results  \u00B7  %.1fs", total, ms / 1000.0));
        totalLbl.getStyleClass().add("summary-total");

        headerBox.getChildren().addAll(title, stats, totalLbl);
        box.getChildren().add(headerBox);

        Separator sep = new Separator();
        sep.getStyleClass().add("summary-separator");
        box.getChildren().add(sep);

        VBox resultList = new VBox(2);
        resultList.getStyleClass().add("summary-results");

        for (String section : dc.getSections()) {
            Label sectionLbl = new Label(section);
            sectionLbl.getStyleClass().add("summary-section-header");
            sectionLbl.setMaxWidth(Double.MAX_VALUE);
            resultList.getChildren().add(sectionLbl);

            for (domain.CheckState cs : dc.getChecksBySection(section)) {
                for (domain.CheckResult r : cs.getResults()) {
                    HBox row = new HBox(8);
                    row.setAlignment(Pos.CENTER_LEFT);
                    row.getStyleClass().addAll("summary-result-row", resultRowClass(r.status()));

                    Label icon = new Label(summaryIcon(r.status()));
                    icon.getStyleClass().addAll("result-icon", summaryIconClass(r.status()));
                    icon.setMinWidth(50);

                    Label msg = new Label(r.message());
                    msg.getStyleClass().add("summary-result-msg");
                    msg.setWrapText(true);
                    HBox.setHgrow(msg, Priority.ALWAYS);

                    row.getChildren().addAll(icon, msg);
                    resultList.getChildren().add(row);

                    if (r.detail() != null && !r.detail().isEmpty()) {
                        Label detail = new Label("   \u2514\u2500 " + r.detail());
                        detail.getStyleClass().add("summary-result-detail");
                        detail.setWrapText(true);
                        resultList.getChildren().add(detail);
                    }
                }
            }
        }

        ScrollPane scrollPane = new ScrollPane(resultList);
        scrollPane.setFitToWidth(true);
        scrollPane.setPrefHeight(320);
        VBox.setVgrow(scrollPane, Priority.ALWAYS);
        box.getChildren().add(scrollPane);

        dialog.getDialogPane().setContent(box);
        dialog.getDialogPane().getButtonTypes().add(ButtonType.OK);
        dialog.getDialogPane().setPrefSize(620, 560);
        dialog.showAndWait();
    }

    private VBox statPill(String number, String label, String type) {
        Label numLbl = new Label(number);
        numLbl.getStyleClass().add("stat-number-" + type);
        Label lblLbl = new Label(label);
        lblLbl.getStyleClass().add("stat-label-" + type);
        VBox pill = new VBox(2, numLbl, lblLbl);
        pill.getStyleClass().addAll("stat-pill", "stat-pill-" + type);
        pill.setAlignment(Pos.CENTER);
        return pill;
    }

    private String summaryIcon(domain.CheckStatus status) {
        return switch (status) {
            case PASS -> "\u2705 PASS";
            case FAIL -> "\u274C FAIL";
            case SKIP -> "\u26A0 SKIP";
            default -> "  \u2014\u2014  ";
        };
    }

    private String summaryIconClass(domain.CheckStatus status) {
        return switch (status) {
            case PASS -> "result-pass";
            case FAIL -> "result-fail";
            case SKIP -> "result-skip";
            default -> "";
        };
    }

    private String resultRowClass(domain.CheckStatus status) {
        return switch (status) {
            case PASS -> "summary-result-row-pass";
            case FAIL -> "summary-result-row-fail";
            case SKIP -> "summary-result-row-skip";
            default -> "";
        };
    }

    void updateStatus() {
        int pass = dc.countPassed();
        int fail = dc.countFailed();
        int skip = dc.countSkipped();
        int total = dc.countTotal();
        long ms = dc.getTotalDuration().toMillis();
        String text = String.format("Results: %d passed, %d failed, %d skipped / %d total",
                pass, fail, skip, total);
        if (ms > 0) {
            text += String.format("  |  Total: %.1fs", ms / 1000.0);
        }
        statusLabel.setText(text);
    }

    void refreshGrid() {
        gridPane.updateAll();
    }
}
