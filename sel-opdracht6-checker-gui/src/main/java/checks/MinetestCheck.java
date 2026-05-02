package checks;

import domain.CheckContext;
import domain.CheckResult;
import domain.SshException;

import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.InetAddress;
import java.util.ArrayList;
import java.util.List;

public class MinetestCheck extends AbstractSSHDependentCheck {

    @Override public String getId() { return "minetest"; }
    @Override public String getName() { return "Minetest UDP port 30000 open"; }
    @Override public String getSection() { return "Minetest"; }
    @Override public String getProtocol() { return "UDP"; }
    @Override public String getPort() { return "30000"; }

    /**
     * Luanti/Minetest TOSERVER_INIT packet (29 bytes, big-endian).
     *
     * Low-level reliable-packet wrapper:
     *   4F 45 74 03  protocol_id (magic)
     *   00 00        sender_peer_id = 0 (new client)
     *   00           channel 0
     *   03           TYPE_RELIABLE
     *   FF FF        seqnum initial
     *   01           PACKET_TYPE_ORIGINAL
     * TOSERVER_INIT payload (command 0x0002):
     *   00 02        command TOSERVER_INIT
     *   1C           max_serialization_ver = 28
     *   00 00        supp_compr_modes = none
     *   00 25        min_net_proto_version = 37
     *   00 25        max_net_proto_version = 37
     *   00 07        player_name length = 7
     *   trouble      player_name
     *
     * Ref: https://github.com/luanti-org/luanti/blob/master/src/network/networkprotocol.h
     */
    private static final byte[] TOSERVER_INIT_PACKET = {
        0x4f, 0x45, 0x74, 0x03,  // protocol_id
        0x00, 0x00,              // sender_peer_id
        0x00,                    // channel
        0x03,                    // TYPE_RELIABLE
        (byte)0xff, (byte)0xff,  // seqnum
        0x01,                    // PACKET_TYPE_ORIGINAL
        0x00, 0x02,              // command: TOSERVER_INIT
        0x1c,                    // max_serialization_ver = 28
        0x00, 0x00,              // supp_compr_modes
        0x00, 0x25,              // min_net_proto_version = 37
        0x00, 0x25,              // max_net_proto_version = 37
        0x00, 0x07,              // player_name length = 7
        't','r','o','u','b','l','e'  // player_name
    };

    @Override
    public List<CheckResult> run(CheckContext ctx) {
        List<CheckResult> skip = requireSsh(ctx, "Minetest check");
        if (skip != null) return skip;

        List<CheckResult> results = new ArrayList<>();

        // 1. Confirm container is running via SSH docker ps
        try {
            String ports = ctx.sshRun("docker ps --filter name=minetest --format '{{.Ports}}' 2>/dev/null");
            if (ports.contains(String.valueOf(ctx.getMinetestPort()))) {
                results.add(CheckResult.pass("Minetest container running with UDP port " + ctx.getMinetestPort() + " mapped"));
            } else {
                String names = ctx.sshRun("docker ps --format '{{.Names}}' 2>/dev/null");
                if (names.toLowerCase().contains("minetest")) {
                    results.add(CheckResult.pass("Minetest container running (port mapping not confirmed)"));
                } else {
                    results.add(CheckResult.fail(
                            "Minetest container not found",
                            "Check if the Minetest container is running"));
                    return results;
                }
            }
        } catch (SshException e) {
            results.add(CheckResult.fail("Minetest SSH check failed", e.getMessage()));
            return results;
        }

        // 2. Send TOSERVER_INIT UDP packet, check for any response
        try (DatagramSocket socket = new DatagramSocket()) {
            socket.setSoTimeout(3000);
            InetAddress addr = InetAddress.getByName(ctx.getTarget());
            int port = ctx.getMinetestPort();

            DatagramPacket send = new DatagramPacket(TOSERVER_INIT_PACKET, TOSERVER_INIT_PACKET.length, addr, port);
            socket.send(send);

            byte[] buf = new byte[512];
            DatagramPacket recv = new DatagramPacket(buf, buf.length);
            socket.receive(recv);  // throws SocketTimeoutException if no response

            results.add(CheckResult.pass(
                    "Minetest server responds on UDP port " + port +
                    " (" + recv.getLength() + " bytes received)"));
        } catch (java.net.SocketTimeoutException e) {
            results.add(CheckResult.fail(
                    "Minetest server not responding on UDP port " + ctx.getMinetestPort(),
                    "Container running but server sent no response — check firewall and port mapping"));
        } catch (Exception e) {
            results.add(CheckResult.fail("Minetest UDP probe failed", e.getMessage()));
        }

        return results;
    }
}
