/**
 * Copyright © 2020-2021 原神資訊站 Genshin Impact Info
 * https://genshininfo.reh.tw/
 *
 * Developed by 旋風之音 GoneTone
 * https://www.facebook.com/GoneToneDY
 */

'use strict'

const { remote } = require('electron')
const fs = require('fs')
const readline = require('readline')
const checkUrl = require('@/modules/checkUrl')

class ReadGenshinFile {
  /**
   * ReadGenshinFile constructor.
   */
  constructor () {
    this._path = `${remote.app.getPath('home')}/AppData/LocalLow/miHoYo/Genshin Impact/`
  }

  /**
   * 取得卡池歷史紀錄頁面網址
   *
   * @returns {Promise<string>}
   */
  getWishHistoryPageUrl () {
    return new Promise((resolve, reject) => {
      const readStream = fs.createReadStream(`${this._path}output_log.txt`).on('error', () => {
        return reject(new Error(window.i18n.t('modules.error.unable_read_log')))
      })

      const rl = readline.createInterface({
        input: readStream,
        output: process.stdout,
        terminal: false
      })

      const wishHistoryPageUrlArray = []
      rl.on('line', (line) => {
        const line2 = line.trim()

        if (line2.startsWith('OnGetWebViewPageFinish:') && line2.endsWith('#/log')) {
          wishHistoryPageUrlArray.push(line2.replace('OnGetWebViewPageFinish:', ''))
        }
      }).on('close', async () => {
        const wishHistoryPageUrl = wishHistoryPageUrlArray.pop()

        if (!wishHistoryPageUrl) {
          return reject(new Error(window.i18n.t('modules.error.unable_get_gacha_history_url')))
        }

        const check = await checkUrl(wishHistoryPageUrl)
        if (check.status) {
          return resolve(wishHistoryPageUrl)
        } else {
          return reject(new Error(window.i18n.t('modules.error.url_verification_failed', { url: wishHistoryPageUrl, msg: check.msg })))
        }
      })
    })
  }

  /**
   * 取得玩家 UID
   *
   * @returns {Promise<string>}
   */
  getPlayerUID () {
    return new Promise((resolve, reject) => {
      const readStream = fs.createReadStream(`${this._path}info.txt`).on('error', () => {
        return reject(new Error(window.i18n.t('modules.error.unable_get_player_uid')))
      })

      const rl = readline.createInterface({
        input: readStream,
        output: process.stdout,
        terminal: false
      })

      let uid = null
      rl.on('line', (line) => {
        const line2 = line.trim()

        if (line2.startsWith('uid:')) {
          uid = line2.replace('uid:', '')
        }
      }).on('close', async () => {
        if (uid === null || uid === '') {
          return reject(new Error(window.i18n.t('modules.error.unable_get_player_uid')))
        }

        return resolve(uid)
      })
    })
  }
}

module.exports = ReadGenshinFile
