/**
 * Copyright © 2020-2021 原神情報站 Genshin Info
 * https://genshininfo.reh.tw/
 *
 * Developed by 旋風之音 GoneTone
 * https://www.facebook.com/GoneToneDY
 */

const electron = require('electron')
const { remote, shell } = electron

const moment = require('moment')

const FileControl = require('@/modules/FileControl')
const ReadGenshinFile = require('@/modules/ReadGenshinFile')
const MiHoYoApi = require('@/modules/MiHoYoApi')
const ExportGachaData = require('@/modules/ExportGachaData')

window.app = remote.app
window.shell = shell

window.moment = moment
window.moment.locale(window.app.getLocale())

window.FileControl = FileControl
window.ReadGenshinFile = ReadGenshinFile
window.MiHoYoApi = MiHoYoApi
window.ExportGachaData = ExportGachaData
