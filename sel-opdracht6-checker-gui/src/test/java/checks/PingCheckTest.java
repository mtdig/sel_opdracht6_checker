package checks;

import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;

class PingCheckTest {

    @Test
    void buildPingCommandUsesWindowsFlags() {
        String previous = System.getProperty("os.name");
        try {
            System.setProperty("os.name", "Windows 11");
            List<String> cmd = PingCheck.buildPingCommand("example.org");

            assertEquals(List.of("ping", "-n", "1", "-w", "5000", "example.org"), cmd);
        } finally {
            restoreOsName(previous);
        }
    }

    @Test
    void buildPingCommandUsesUnixFlags() {
        String previous = System.getProperty("os.name");
        try {
            System.setProperty("os.name", "Linux");
            List<String> cmd = PingCheck.buildPingCommand("example.org");

            assertEquals(List.of("ping", "-c", "1", "-W", "5", "example.org"), cmd);
        } finally {
            restoreOsName(previous);
        }
    }

    private static void restoreOsName(String previous) {
        if (previous == null) {
            System.clearProperty("os.name");
        } else {
            System.setProperty("os.name", previous);
        }
    }
}
