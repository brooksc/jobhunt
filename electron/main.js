// Electron main process: starts the Express server then opens a BrowserWindow.
import { app, BrowserWindow, shell, globalShortcut, Notification } from 'electron';
import path from 'path';
import os from 'os';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const appIconPath = path.join(__dirname, '../static/icons/icon-512.png');

let mainWindow = null;
let serverPort = null;

function pluralize(count, singular, plural = `${singular}s`) {
  return count === 1 ? singular : plural;
}

function truncateText(value, maxLength = 120) {
  const text = String(value || '').replace(/\s+/g, ' ').trim();
  if (text.length <= maxLength) return text;
  return `${text.slice(0, maxLength - 1)}…`;
}

function showMacNotification({ title, body, critical = false }) {
  if (process.platform !== 'darwin' || !Notification.isSupported()) return;
  if (!critical && mainWindow?.isFocused()) return;
  new Notification({ title, body }).show();
  if (mainWindow && !mainWindow.isFocused()) mainWindow.flashFrame?.(true);
}

process.on('jobhunt:job-added', ({ jobNumber, pageTitle, duplicateOfJobId } = {}) => {
  const title = duplicateOfJobId ? 'Jobhunt — Possible duplicate added' : 'Jobhunt — Job added';
  const jobLabel = jobNumber ? `#${jobNumber}` : 'New job';
  const body = pageTitle
    ? `${jobLabel}: ${truncateText(pageTitle)}`
    : `${jobLabel} was saved.`;
  showMacNotification({ title, body });
});

process.on('jobhunt:ai-processing-complete', ({ processed = 0, succeeded = 0, failed = 0 } = {}) => {
  if (!processed) return;
  const itemLabel = pluralize(processed, 'AI item');
  const title = failed > 0 ? 'Jobhunt — AI processing finished with errors' : 'Jobhunt — AI processing complete';
  const body = `${processed} ${itemLabel} processed: ${succeeded} succeeded, ${failed} failed.`;
  showMacNotification({ title, body });
});

// Fired by extract.js when 2 consecutive LLM failures auto-pause the queue.
process.on('jobhunt:queue-auto-paused', () => {
  showMacNotification({
    title: 'Jobhunt — AI extraction paused',
    body: '2 consecutive failures stopped the queue. Open LLM Queue to review errors and resume.',
    critical: true,
  });
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

  function applyZoom() {
    if (!mainWindow || mainWindow.isDestroyed()) return;
    const [w] = mainWindow.getContentSize();
    const factor = Math.min(1.0, Math.max(0.5, w / DESIGN_WIDTH));
    mainWindow.webContents.setZoomFactor(factor);
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
  // Make the brand row and the tl-space (traffic-light spacer) draggable so users
  // can move the window from the sidebar area.  The spacer is already -webkit-app-region:drag
  // via CSS; this covers the brand text row too.
  mainWindow.webContents.insertCSS(`
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
