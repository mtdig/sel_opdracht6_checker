package main;

import domain.DomainController;
import gui.MainPane;
import javafx.application.Application;
import javafx.scene.Scene;
import javafx.stage.Stage;

public class StartUp extends Application {

    @Override
    public void start(Stage primaryStage) {
        DomainController dc = new DomainController();
        MainPane mainPane = new MainPane(dc);

        Scene scene = new Scene(mainPane, 960, 640);
        scene.getStylesheets().add(getClass().getResource("/style.css").toExternalForm());
        primaryStage.setScene(scene);
        primaryStage.setTitle("SELab Opdracht 6 Checker");
        primaryStage.show();
    }

    public static void main(String[] args) {
        launch(args);
    }
}
