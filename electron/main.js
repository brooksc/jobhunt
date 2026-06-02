// Electron main process: starts the Express server then opens a BrowserWindow.
import { app, BrowserWindow, shell, globalShortcut, Notification } from 'electron';
import path from 'path';
import os from 'os';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const appIconPath = path.join(__dirname, '../static/icons/icon-512.png');

let mainWindow = null;
let serverPort = null;

// Fired by extract.js when 2 consecutive LLM failures auto-pause the queue.
process.on('jobhunt:queue-auto-paused', () => {
  if (Notification.isSupported()) {
    new Notification({
      title: 'Jobhunt — AI extraction paused',
      body: '2 consecutive failures stopped the queue. Open LLM Queue to review errors and resume.',
    }).show();
  }
  // Also flash the window if it exists and isn't focused.
  if (mainWindow && !mainWindow.isFocused()) mainWindow.flashFrame?.(true);
});

async function startServer() {
  // Use the same DB as the CLI server: ~/.config/jobhunt/jobhunt.db
  // Respect JOBHUNT_DB_PATH if already set (same convention as the CLI).
  const dbPath = process.env.JOBHUNT_DB_PATH
    || path.join(os.homedir(), '.config', 'jobhunt', 'jobhunt.db');
  process.env.JOBHUNT_DB_PATH = dbPath;

  const { initDb, requeueRunningRequests } = await import('../server/db.js');
  initDb(dbPath);
  requeueRunningRequests(dbPath, 0);

  const { createApp } = await import('../server/api.js');
  const expressApp = createApp({ dbPath, autoExtract: true });

  // Try preferred ports in order so the extension can find us predictably.
  // Fall back to an OS-assigned port if all are busy.
  const PREFERRED_PORTS = [8765, 8766, 8767, 8768, 8769];

  const tryPort = (port) => new Promise((resolve, reject) => {
    const server = expressApp.listen(port, '127.0.0.1', () => resolve(server));
    server.on('error', reject);
  });

  for (const port of PREFERRED_PORTS) {
    try {
      const server = await tryPort(port);
      return server.address().port;
    } catch (err) {
      if (err.code !== 'EADDRINUSE') throw err;
    }
  }
  throw new Error(`No preferred extension port available: ${PREFERRED_PORTS.join(', ')}`);
}

async function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1280,
    height: 860,
    minWidth: 960,
    minHeight: 600,
    show: false,
    resizable: true,
    icon: appIconPath,
    titleBarStyle: 'hiddenInset',
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
    },
  });

  // Scale page content proportionally to window width so nothing overflows.
  // At the design width (1280px) zoom = 1.0; shrinks gracefully for smaller windows.
  const DESIGN_WIDTH = 1280;
  // Physical px of clearance needed above the sidebar brand row to clear traffic lights.
  const TRAFFIC_PAD_PX = 36;

  function applyZoom() {
    if (!mainWindow || mainWindow.isDestroyed()) return;
    const [w] = mainWindow.getContentSize();
    const factor = Math.min(1.0, Math.max(0.5, w / DESIGN_WIDTH));
    mainWindow.webContents.setZoomFactor(factor);
    // CSS pixels shrink as zoom decreases, so physical clearance shrinks too.
    // Invert the zoom so the sidebar top padding stays ~36 physical pixels.
    const cssPad = Math.ceil(TRAFFIC_PAD_PX / factor);
    mainWindow.webContents.executeJavaScript(
      `document.documentElement.style.setProperty('--electron-sidebar-pad', '${cssPad}px')`,
      true
    ).catch(() => {});
  }
  mainWindow.on('resize', applyZoom);

  mainWindow.once('ready-to-show', () => {
    applyZoom();
    mainWindow.show();
  });

  // Open external links in the system browser, not inside the app
  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    if (!url.startsWith('http://127.0.0.1')) shell.openExternal(url);
    return { action: 'deny' };
  });

  await mainWindow.loadURL(`http://127.0.0.1:${serverPort}`);

  // Push sidebar content down so macOS traffic lights don't overlap.
  // hiddenInset places buttons at ~(10,10); brand row is the first thing in the sidebar.
  // Do NOT set -webkit-app-region:drag on .jh-side — it covers the left/top window edges
  // and causes macOS to treat resize-drags as window-move events (window won't resize).
  mainWindow.webContents.insertCSS(`
    .jh-side { padding-top: var(--electron-sidebar-pad, 36px) !important; }
    .jh-side__brand { -webkit-app-region: drag; }
    .jh-side__brand * { -webkit-app-region: no-drag; }
  `);

  mainWindow.on('closed', () => { mainWindow = null; });
}

app.whenReady().then(async () => {
  try {
    serverPort = await startServer();
    await createWindow();
  } catch (err) {
    console.error('Failed to start:', err);
    app.quit();
  }

  // Cmd+Option+I → toggle DevTools
  globalShortcut.register('CommandOrControl+Alt+I', () => {
    if (mainWindow) mainWindow.webContents.toggleDevTools();
  });

  // macOS: re-open window when clicking dock icon with no windows open
  app.on('activate', () => {
    if (!mainWindow && serverPort) createWindow();
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});
