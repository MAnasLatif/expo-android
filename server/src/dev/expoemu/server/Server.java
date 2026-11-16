package dev.expoemu.server;

import android.accessibilityservice.AccessibilityServiceInfo;
import android.app.Activity;
import android.app.Instrumentation;
import android.app.UiAutomation;
import android.content.Context;
import android.graphics.Point;
import android.graphics.Rect;
import android.hardware.display.DisplayManager;
import android.os.Build;
import android.os.Bundle;
import android.os.SystemClock;
import android.util.Log;
import android.util.Xml;
import android.view.Display;
import android.view.accessibility.AccessibilityNodeInfo;

import org.xmlpull.v1.XmlSerializer;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.io.StringWriter;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.net.SocketTimeoutException;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.TimeoutException;

/**
 * expoemu UI server.
 *
 * Started with:
 *   am instrument -w -e token T [-e port P] [-e idle_exit_s S] dev.expoemu.server/.Server
 *
 * Keeps one UiAutomation connection open and serves, on 127.0.0.1 only:
 *   GET /ping   -> "expoemu-ui-server VERSION"
 *   GET /dump   -> the same XML that `uiautomator dump` writes
 *                  (optional ?idle=MS: how long the UI must be quiet first)
 *   GET /quit   -> stops the server
 * Every request must send the header "X-Token: T". The token keeps other apps
 * on the device from reading the screen through the local port.
 *
 * The server exits by itself after idle_exit_s seconds without requests, so
 * nothing stays running (or connected to accessibility) when unused.
 */
public final class Server extends Instrumentation {
    private static final String TAG = "expoemu-ui";
    private static final int DEFAULT_PORT = 47219;
    private static final int DEFAULT_IDLE_EXIT_S = 900;
    private static final long DEFAULT_IDLE_MS = 150;
    private static final long MAX_IDLE_WAIT_MS = 2000;

    // Same exclusions as uiautomator's AccessibilityNodeInfoDumper (NAF check).
    private static final String[] NAF_EXCLUDED_CLASSES = {
        "android.widget.GridView", "android.widget.GridLayout",
        "android.widget.ListView", "android.widget.TabWidget",
    };

    private String token = "";
    private int port = DEFAULT_PORT;
    private int idleExitS = DEFAULT_IDLE_EXIT_S;
    private String version = "unknown";
    private UiAutomation automation;

    @Override
    public void onCreate(Bundle args) {
        super.onCreate(args);
        if (args != null) {
            token = nonNull(args.getString("token"));
            port = intArg(args.getString("port"), DEFAULT_PORT);
            idleExitS = intArg(args.getString("idle_exit_s"), DEFAULT_IDLE_EXIT_S);
        }
        try {
            Context c = getContext();
            version = nonNull(c.getPackageManager().getPackageInfo(c.getPackageName(), 0).versionName);
        } catch (Exception e) {
            Log.w(TAG, "no version", e);
        }
        start(); // runs onStart() on a new thread
    }

    @Override
    public void onStart() {
        Bundle result = new Bundle();
        try {
            serve();
            result.putString("result", "stopped");
            finish(Activity.RESULT_OK, result);
        } catch (Throwable t) {
            Log.e(TAG, "server failed", t);
            result.putString("error", String.valueOf(t));
            finish(Activity.RESULT_CANCELED, result);
        }
    }

    // --- HTTP ------------------------------------------------------------------

    private void serve() throws Exception {
        ServerSocket server = new ServerSocket();
        server.setReuseAddress(true);
        server.bind(new InetSocketAddress(InetAddress.getByName("127.0.0.1"), port));
        server.setSoTimeout(30_000);
        Log.i(TAG, "listening on 127.0.0.1:" + port + " version " + version);
        long last = SystemClock.elapsedRealtime();
        try {
            while (true) {
                Socket socket;
                try {
                    socket = server.accept();
                } catch (SocketTimeoutException e) {
                    if (SystemClock.elapsedRealtime() - last > idleExitS * 1000L) {
                        Log.i(TAG, "idle for " + idleExitS + " s, exiting");
                        return;
                    }
                    continue;
                }
                last = SystemClock.elapsedRealtime();
                boolean quit = false;
                try {
                    quit = handle(socket);
                } catch (Exception e) {
                    Log.w(TAG, "request failed", e);
                } finally {
                    try { socket.close(); } catch (Exception ignored) { }
                }
                if (quit) return;
            }
        } finally {
            server.close();
        }
    }

    /** Handles one request. Returns true when the server should stop. */
    private boolean handle(Socket socket) throws Exception {
        socket.setSoTimeout(5_000);
        BufferedReader in = new BufferedReader(
                new InputStreamReader(socket.getInputStream(), StandardCharsets.UTF_8));
        String requestLine = in.readLine();
        if (requestLine == null) return false;
        String sentToken = "";
        String line;
        while ((line = in.readLine()) != null && !line.isEmpty()) {
            int colon = line.indexOf(':');
            if (colon > 0 && line.substring(0, colon).trim().equalsIgnoreCase("X-Token")) {
                sentToken = line.substring(colon + 1).trim();
            }
        }
        OutputStream out = socket.getOutputStream();
        String[] parts = requestLine.split(" ");
        if (parts.length < 2 || !"GET".equals(parts[0])) {
            respond(out, 405, "text/plain", "method not allowed\n");
            return false;
        }
        if (!token.equals(sentToken)) {
            respond(out, 403, "text/plain", "bad token\n");
            return false;
        }
        String target = parts[1];
        String path = target;
        String query = "";
        int q = target.indexOf('?');
        if (q >= 0) { path = target.substring(0, q); query = target.substring(q + 1); }

        switch (path) {
            case "/ping":
                respond(out, 200, "text/plain", "expoemu-ui-server " + version + "\n");
                return false;
            case "/dump": {
                long idle = longParam(query, "idle", DEFAULT_IDLE_MS);
                String xml = dump(idle);
                if (xml == null) {
                    respond(out, 503, "text/plain", "no active window\n");
                } else {
                    respond(out, 200, "application/xml; charset=utf-8", xml);
                }
                return false;
            }
            case "/quit":
                respond(out, 200, "text/plain", "bye\n");
                return true;
            default:
                respond(out, 404, "text/plain", "not found\n");
                return false;
        }
    }

    private static void respond(OutputStream out, int status, String type, String body) throws Exception {
        byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
        String reason = status == 200 ? "OK" : "Error";
        String head = "HTTP/1.1 " + status + " " + reason + "\r\n"
                + "Content-Type: " + type + "\r\n"
                + "Content-Length: " + bytes.length + "\r\n"
                + "Connection: close\r\n\r\n";
        out.write(head.getBytes(StandardCharsets.US_ASCII));
        out.write(bytes);
        out.flush();
    }

    // --- UI dump (format identical to `uiautomator dump`) ---------------------

    private synchronized UiAutomation automation() {
        if (automation == null) {
            // Keep TalkBack & co. running while we are connected.
            UiAutomation ua = getUiAutomation(UiAutomation.FLAG_DONT_SUPPRESS_ACCESSIBILITY_SERVICES);
            AccessibilityServiceInfo info = ua.getServiceInfo();
            if (info != null) {
                // Match `uiautomator dump`: every view (layout wrappers too,
                // so child indexes line up) and resource ids (testIDs).
                info.flags |= AccessibilityServiceInfo.FLAG_INCLUDE_NOT_IMPORTANT_VIEWS
                        | AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS;
                ua.setServiceInfo(info);
            }
            automation = ua;
        }
        return automation;
    }

    private String dump(long idleMs) throws Exception {
        UiAutomation ua = automation();
        if (idleMs > 0) {
            try {
                ua.waitForIdle(idleMs, Math.max(idleMs, MAX_IDLE_WAIT_MS));
            } catch (TimeoutException ignored) {
                // Still animating: dump what is there, like a poll would.
            }
        }
        AccessibilityNodeInfo root = null;
        for (int i = 0; i < 20 && root == null; i++) {
            root = ua.getRootInActiveWindow();
            if (root == null) SystemClock.sleep(50);
        }
        if (root == null) return null;

        DisplayManager dm = (DisplayManager) getContext().getSystemService(Context.DISPLAY_SERVICE);
        Display display = dm.getDisplay(Display.DEFAULT_DISPLAY);
        Point size = new Point();
        display.getRealSize(size);

        StringWriter writer = new StringWriter();
        XmlSerializer xml = Xml.newSerializer();
        xml.setOutput(writer);
        xml.startDocument("UTF-8", true);
        xml.startTag("", "hierarchy");
        xml.attribute("", "rotation", Integer.toString(display.getRotation()));
        dumpNode(root, xml, 0, size.x, size.y);
        xml.endTag("", "hierarchy");
        xml.endDocument();
        return writer.toString();
    }

    private static void dumpNode(AccessibilityNodeInfo node, XmlSerializer xml, int index,
                                 int width, int height) throws Exception {
        xml.startTag("", "node");
        if (!nafExcludedClass(node) && !nafCheck(node)) {
            xml.attribute("", "NAF", Boolean.toString(true));
        }
        xml.attribute("", "index", Integer.toString(index));
        xml.attribute("", "text", safe(node.getText()));
        xml.attribute("", "resource-id", safe(node.getViewIdResourceName()));
        xml.attribute("", "class", safe(node.getClassName()));
        xml.attribute("", "package", safe(node.getPackageName()));
        xml.attribute("", "content-desc", safe(node.getContentDescription()));
        xml.attribute("", "checkable", Boolean.toString(node.isCheckable()));
        xml.attribute("", "checked", Boolean.toString(node.isChecked()));
        xml.attribute("", "clickable", Boolean.toString(node.isClickable()));
        xml.attribute("", "enabled", Boolean.toString(node.isEnabled()));
        xml.attribute("", "focusable", Boolean.toString(node.isFocusable()));
        xml.attribute("", "focused", Boolean.toString(node.isFocused()));
        xml.attribute("", "scrollable", Boolean.toString(node.isScrollable()));
        xml.attribute("", "long-clickable", Boolean.toString(node.isLongClickable()));
        xml.attribute("", "password", Boolean.toString(node.isPassword()));
        xml.attribute("", "selected", Boolean.toString(node.isSelected()));
        xml.attribute("", "bounds", visibleBounds(node, width, height).toShortString());
        xml.attribute("", "drawing-order", Integer.toString(node.getDrawingOrder()));
        if (Build.VERSION.SDK_INT >= 26) {
            xml.attribute("", "hint", safe(node.getHintText()));
        }
        int count = node.getChildCount();
        for (int i = 0; i < count; i++) {
            AccessibilityNodeInfo child = node.getChild(i);
            if (child != null && child.isVisibleToUser()) {
                dumpNode(child, xml, i, width, height);
            }
        }
        xml.endTag("", "node");
    }

    private static Rect visibleBounds(AccessibilityNodeInfo node, int width, int height) {
        Rect bounds = new Rect();
        node.getBoundsInScreen(bounds);
        if (!bounds.intersect(0, 0, width, height)) return new Rect();
        return bounds;
    }

    private static boolean nafExcludedClass(AccessibilityNodeInfo node) {
        String cls = safe(node.getClassName());
        for (String excluded : NAF_EXCLUDED_CLASSES) {
            if (cls.endsWith(excluded)) return true;
        }
        return false;
    }

    /** False when the node is clickable but has no text or label anywhere in it. */
    private static boolean nafCheck(AccessibilityNodeInfo node) {
        boolean naf = node.isClickable() && node.isEnabled()
                && safe(node.getContentDescription()).isEmpty()
                && safe(node.getText()).isEmpty();
        return !naf || childNafCheck(node);
    }

    private static boolean childNafCheck(AccessibilityNodeInfo node) {
        int count = node.getChildCount();
        for (int i = 0; i < count; i++) {
            AccessibilityNodeInfo child = node.getChild(i);
            if (child == null) continue;
            if (!safe(child.getContentDescription()).isEmpty() || !safe(child.getText()).isEmpty()) return true;
            if (childNafCheck(child)) return true;
        }
        return false;
    }

    /** Like uiautomator: null becomes "", characters XML can't hold become ".". */
    private static String safe(CharSequence cs) {
        if (cs == null) return "";
        StringBuilder sb = new StringBuilder(cs.length());
        for (int i = 0; i < cs.length(); i++) {
            char ch = cs.charAt(i);
            boolean invalid = (ch < 0x20 && ch != 0x9 && ch != 0xA && ch != 0xD)
                    || (ch >= 0x7F && ch <= 0x84) || (ch >= 0x86 && ch <= 0x9F)
                    || (ch >= 0xFDD0 && ch <= 0xFDDF) || ch == 0xFFFE || ch == 0xFFFF;
            sb.append(invalid ? '.' : ch);
        }
        return sb.toString();
    }

    // --- small helpers -----------------------------------------------------------

    private static String nonNull(String s) { return s == null ? "" : s; }

    private static int intArg(String s, int fallback) {
        try { return s == null ? fallback : Integer.parseInt(s.trim()); } catch (NumberFormatException e) { return fallback; }
    }

    private static long longParam(String query, String name, long fallback) {
        for (String pair : query.split("&")) {
            int eq = pair.indexOf('=');
            if (eq > 0 && pair.substring(0, eq).equals(name)) {
                try { return Long.parseLong(pair.substring(eq + 1)); } catch (NumberFormatException e) { return fallback; }
            }
        }
        return fallback;
    }
}
