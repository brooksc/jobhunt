// Electron main process: starts the Express server then opens a BrowserWindow.
import { app, BrowserWindow, shell, globalShortcut, Notification } from 'electron';
import path from 'path';
import os from 'os';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const appIconPath = path.join(__dirname, '../static/icons/icon-512.png');

let mainWindow = null;
let serverPort = null;
let pendingDeepLink = null;

// Register jobhunt:// URL scheme so macOS can open the app from external links.
// In dev mode (process.defaultApp is set) we must pass the script path explicitly.
if (process.defaultApp && process.argv.length >= 2) {
  app.setAsDefaultProtocolClient('jobhunt', process.execPath, [path.resolve(process.argv[1])]);
} else {
  app.setAsDefaultProtocolClient('jobhunt');
}

// Must be registered before app.whenReady() on macOS.
app.on('open-url', (event, url) => {
  event.preventDefault();
  if (mainWindow) {
    focusWindow();
    navigateDeepLink(url);
  } else {
    pendingDeepLink = url;
  }
});

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

// Called by the server API bridge (/api/app/focus) and open-url handler.
process.on('jobhunt:open-job', ({ jobNumber } = {}) => {
  if (!mainWindow) return;
  focusWindow();
  if (jobNumber) navigateToJob(jobNumber);
});

function focusWindow() {
  if (!mainWindow) return;
  if (mainWindow.isMinimized()) mainWindow.restore();
  mainWindow.focus();
}

function navigateToJob(jobNumber) {
  if (!mainWindow || mainWindow.isDestroyed()) return;
  const hash = JSON.stringify(`#/jobs/${jobNumber}`);
  // Refresh UI data so the new job appears in JH_JOBS, then push the hash
  // via history.pushState so the app's popstate handler selects the row and
  // opens the detail pane.
  const script = `(async () => {
    await window.JH_REFRESH_UI_DATA?.();
    await new Promise(r => setTimeout(r, 400));
    history.pushState(null, '', ${hash});
    window.dispatchEvent(new PopStateEvent('popstate', { state: null }));
  })()`;
  if (mainWindow.webContents.isLoading()) {
    mainWindow.webContents.once('did-finish-load', () => {
      mainWindow.webContents.executeJavaScript(script).catch(() => {});
    });
  } else {
    mainWindow.webContents.executeJavaScript(script).catch(() => {});
  }
}

function navigateDeepLink(url) {
  // jobhunt://jobs/42
  const match = url.match(/^jobhunt:\/\/jobs\/(\d+)/i);
  if (match) navigateToJob(parseInt(match[1], 10));
}

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
  const { DEMO_DB_PATH } = await import('../server/demo.js');
  const expressApp = createApp({ dbPath, autoExtract: true, demoDemoPath: DEMO_DB_PATH });

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
    // Handle URL that arrived before window was ready (open-url fired during startup)
    if (pendingDeepLink) {
      navigateDeepLink(pendingDeepLink);
      pendingDeepLink = null;
    }
  });

  // Open external links in the system browser, not inside the app
  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    if (!url.startsWith('http://127.0.0.1')) shell.openExternal(url);
    return { action: 'deny' };
  });

  await mainWindow.loadURL(`http://127.0.0.1:${serverPort}`);

  mainWindow.on('closed', () => { mainWindow = null; });
}

app.whenReady().then(async () => {
  // On macOS the URL can arrive in argv when the app is launched cold via the scheme.
  const argUrl = process.argv.find(a => a.startsWith('jobhunt://'));
  if (argUrl && !pendingDeepLink) pendingDeepLink = argUrl;

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
