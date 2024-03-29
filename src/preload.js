/**
 * Copyright © 2020-2021 原神資訊站 Genshin Impact Info
 * https://genshininfo.reh.tw/
 *
 * Developed by 旋風之音 GoneTone
 * https://www.facebook.com/GoneToneDY
 */

const electron = require('electron')
const { remote, shell, ipcRenderer } = electron

const { Titlebar, Color } = require('custom-electron-titlebar')

const log = require('electron-log')
log.transports.console.level = false

const moment = require('moment')
const GitHub = require('github-api')
const showdown = require('showdown')
const hoyowikiApi = require('@gonetone/hoyowiki-api')

const FileControl = require('@/modules/FileControl')
const ReadGenshinFile = require('@/modules/ReadGenshinFile')
const MiHoYoApi = require('@/modules/MiHoYoApi')
const ExportGachaData = require('@/modules/ExportGachaData')

window.app = remote.app
window.shell = shell
window.ipcRenderer = ipcRenderer

window.log = log

window.moment = moment
window.moment.locale(window.app.getLocale())

window.github = new GitHub()

showdown.setFlavor('github')
window.mdConverter = new showdown.Converter()

hoyowikiApi.axiosInstance.defaults.adapter = require('axios/lib/adapters/http')
window.hoyowikiApi = hoyowikiApi

window.FileControl = FileControl
window.ReadGenshinFile = ReadGenshinFile
window.MiHoYoApi = MiHoYoApi
window.ExportGachaData = ExportGachaData

window.addEventListener('DOMContentLoaded', () => {
  window.titlebar = new Titlebar({
    backgroundColor: Color.fromHex('#2f3241'),
    icon: '../build/icons/256x256.png'
  })
})
