package gui;

import domain.DomainController;
import domain.SecretDecryptionException;
import domain.SecretsDecryptor;
import javafx.application.Platform;
import javafx.scene.control.*;
import javafx.scene.layout.Priority;
import javafx.scene.layout.VBox;

import java.util.Map;


public class SidePanel extends VBox {

    private final DomainController dc;
    private final MainPane mainPane;

    private TextField targetField;
    private TextField userField;
    private PasswordField passphraseField;
    private Label statusLabel;
    private Button runAllBtn;

    public SidePanel(DomainController dc, MainPane mainPane) {
        this.dc = dc;
        this.mainPane = mainPane;
        buildUI();
    }

    private void buildUI() {
        getStyleClass().add("side-panel");
        setPrefWidth(260);

        Label title = new Label("Configuration");
        title.getStyleClass().add("side-title");

        Label targetLbl = new Label("Target (hostname/IP)");
        targetLbl.getStyleClass().add("side-label");
        targetField = new TextField();
        targetField.setPromptText("e.g. 192.168.56.20");
        targetField.getStyleClass().add("dark-field");
        targetField.setText("192.168.56.20");
        targetField.setMaxWidth(Double.MAX_VALUE);

        Label userLbl = new Label("Local user");
        userLbl.getStyleClass().add("side-label");
        userField = new TextField();
        userField.setPromptText(System.getProperty("user.name", "student"));
        userField.getStyleClass().add("dark-field");
        userField.setText(System.getProperty("user.name", "student"));
        userField.setMaxWidth(Double.MAX_VALUE);

        getChildren().addAll(title, targetLbl, targetField, userLbl, userField);

        Separator sep1 = new Separator();
        sep1.getStyleClass().add("dark-separator");
        getChildren().add(sep1);

        Label passLbl = new Label("Decryption passphrase");
        passLbl.getStyleClass().add("side-label");
        passphraseField = new PasswordField();
        passphraseField.setPromptText("passphrase for secrets.env.enc");
        passphraseField.getStyleClass().add("dark-field");
        passphraseField.setMaxWidth(Double.MAX_VALUE);

        Label hint = new Label("Embedded secrets are decrypted at runtime");
        hint.getStyleClass().add("side-hint");

        getChildren().addAll(passLbl, passphraseField, hint);

        Separator sep2 = new Separator();
        sep2.getStyleClass().add("dark-separator");
        getChildren().add(sep2);

        statusLabel = new Label("");
        statusLabel.getStyleClass().add("side-status");
        getChildren().add(statusLabel);

        VBox spacer = new VBox();
        VBox.setVgrow(spacer, Priority.ALWAYS);
        getChildren().add(spacer);

        runAllBtn = new Button("Run All");
        runAllBtn.getStyleClass().add("btn-primary");
        runAllBtn.setMaxWidth(Double.MAX_VALUE);
        runAllBtn.setOnAction(e -> onRunAll());

        Button exitBtn = new Button("Exit");
        exitBtn.getStyleClass().add("btn-danger");
        exitBtn.setMaxWidth(Double.MAX_VALUE);
        exitBtn.setOnAction(e -> {
            dc.close();
            Platform.exit();
        });

        getChildren().addAll(runAllBtn, exitBtn);
    }

    private void onRunAll() {
        statusLabel.setText("");

        String target = targetField.getText().trim();
        if (target.isEmpty()) {
            statusLabel.getStyleClass().setAll("side-status");
            statusLabel.setText("Target is required.");
            return;
        }

        String passphrase = passphraseField.getText();
        if (passphrase.isEmpty()) {
            statusLabel.getStyleClass().setAll("side-status");
            statusLabel.setText("Passphrase is required.");
            return;
        }

        Map<String, String> secrets;
        try {
            secrets = SecretsDecryptor.decrypt(passphrase,
                    "SSH_USER", "SSH_PASS",
                    "MYSQL_REMOTE_USER", "MYSQL_REMOTE_PASS",
                    "MYSQL_LOCAL_USER", "MYSQL_LOCAL_PASS",
                    "WP_USER", "WP_PASS");
        } catch (SecretDecryptionException ex) {
            statusLabel.getStyleClass().setAll("side-status");
            statusLabel.setText("Decryption failed: " + ex.getMessage());
            return;
        }

        statusLabel.getStyleClass().setAll("side-status-ok");
        statusLabel.setText("Secrets decrypted OK — running checks...");

        dc.configure(target, userField.getText().trim(), secrets);
        setRunning(true);
        dc.runAll();
    }

    void setRunning(boolean running) {
        runAllBtn.setDisable(running);
        runAllBtn.setText(running ? "Running..." : "Run All");
    }
}
