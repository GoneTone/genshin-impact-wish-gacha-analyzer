/**
 * Copyright © 2020-2021 原神情報站 Genshin Info
 * https://genshininfo.reh.tw/
 *
 * Developed by 旋風之音 GoneTone
 * https://www.facebook.com/GoneToneDY
 */

/* global __static */

'use strict'

import { app, protocol, BrowserWindow, Menu, screen } from 'electron'
import { createProtocol } from 'vue-cli-plugin-electron-builder/lib'
import installExtension, { VUEJS_DEVTOOLS } from 'electron-devtools-installer'

const isDevelopment = process.env.NODE_ENV !== 'production'

const path = require('path')
const windowStateKeeper = require('electron-window-state')
const log = require('electron-log')

log.info('應用程式啟動...')

// Scheme must be registered before the app is ready
protocol.registerSchemesAsPrivileged([
  {
    scheme: 'app',
    privileges: {
      secure: true,
      standard: true,
      stream: true
    }
  }
])

async function createWindow () {
  log.info('視窗創建...')

  const { width, height } = screen.getPrimaryDisplay().workAreaSize

  let defaultWidth = Math.round((width - 100))
  let defaultHeight = Math.round((height - 100))
  if (width > height) {
    // 16:9
    defaultWidth = Math.round((((height - 100) * 16) / 9))
    defaultHeight = Math.round(((defaultWidth * 9) / 16))
  }
  if (height > width) {
    // 9:16
    defaultWidth = Math.round((((width - 100) * 9) / 16))
    defaultHeight = Math.round(((defaultWidth * 16) / 9))
  }

  // Load the previous state with fallback to defaults
  const mainWindowState = windowStateKeeper({
    defaultWidth: defaultWidth,
    defaultHeight: defaultHeight
  })

  const setX = mainWindowState.x
  const setY = mainWindowState.y
  const setWidth = mainWindowState.width
  const setHeight = mainWindowState.height
  const isMaximized = mainWindowState.isMaximized

  if (isMaximized) {
    log.info('視窗大小設定為最大化。')
  } else {
    log.info(`視窗大小設定為 ${setWidth}*${setHeight}。`)
  }

  Menu.setApplicationMenu(null)

  // Create the window using the state information
  const win = new BrowserWindow({
    x: setX,
    y: setY,
    width: setWidth,
    height: setHeight,
    title: process.env.VUE_APP_NAME, // 應用程式標題
    icon: path.join(__static, 'icon.png'), // 應用程式 Icon
    webPreferences: {
      // Use pluginOptions.nodeIntegration, leave this alone
      // See nklayman.github.io/vue-cli-plugin-electron-builder/guide/security.html#node-integration for more info
      nodeIntegration: process.env.ELECTRON_NODE_INTEGRATION,
      enableRemoteModule: true,
      preload: path.join(__dirname, 'preload.js')
    }
  })

  // Let us register listeners on the window, so we can update the state
  // automatically (the listeners will be removed when the window is closed)
  // and restore the maximized or full screen state
  mainWindowState.manage(win)

  if (process.env.WEBPACK_DEV_SERVER_URL) {
    // Load the url of the dev server if in development mode
    await win.loadURL(process.env.WEBPACK_DEV_SERVER_URL)
    if (!process.env.IS_TEST) win.webContents.openDevTools()
  } else {
    createProtocol('app')
    // Load the index.html when not in development
    await win.loadURL('app://./index.html')
  }
}

// Quit when all windows are closed.
app.on('window-all-closed', () => {
  // On macOS it is common for applications and their menu bar
  // to stay active until the user quits explicitly with Cmd + Q
  if (process.platform !== 'darwin') {
    log.info('應用程式關閉。')
    app.quit()
  }
})

app.on('activate', () => {
  // On macOS it's common to re-create a window in the app when the
  // dock icon is clicked and there are no other windows open.
  if (BrowserWindow.getAllWindows().length === 0) createWindow().then()
})

// This method will be called when Electron has finished
// initialization and is ready to create browser windows.
// Some APIs can only be used after this event occurs.
app.on('ready', async () => {
  if (isDevelopment && !process.env.IS_TEST) {
    // Install Vue Devtools
    try {
      await installExtension(VUEJS_DEVTOOLS)
    } catch (e) {
      console.error('Vue Devtools failed to install:', e.toString())
    }
  }
  await createWindow()
})

// Exit cleanly on request from parent process in development mode.
if (isDevelopment) {
  if (process.platform === 'win32') {
    process.on('message', (data) => {
      if (data === 'graceful-exit') {
        app.quit()
      }
    })
  } else {
    process.on('SIGTERM', () => {
      app.quit()
    })
  }
}
