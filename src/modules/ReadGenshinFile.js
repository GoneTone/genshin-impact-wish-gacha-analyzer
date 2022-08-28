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
const Registry = require('winreg')
const Proxy = require('http-mitm-proxy')

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
    /* 設定 Proxy */
    const setProxy = async (enable, proxyIp = '', ignoreIp = '') => {
      const regKey = new Registry({
        hive: Registry.HKCU,
        key: '\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings'
      })

      const regSet = function (key, type, value) {
        return new Promise((resolve, reject) => {
          regKey.set(key, type, value, function (err) {
            if (err) reject(err)
            resolve()
          })
        })
      }
      await regSet('ProxyEnable', Registry.REG_DWORD, enable)
      await regSet('ProxyServer', Registry.REG_SZ, proxyIp)
      await regSet('ProxyOverride', Registry.REG_SZ, ignoreIp)
    }

    return new Promise((resolve, reject) => {
      /*
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
      */

      const proxyPort = 7097

      const proxyIp = `127.0.0.1:${proxyPort}`
      const ignoreIp = 'localhost;127.*;10.*;172.16.*;172.17.*;172.18.*;172.19.*;172.20.*;172.21.*;172.22.*;172.23.*;172.24.*;172.25.*;172.26.*;172.27.*;172.28.*;172.29.*;172.30.*;172.31.*;192.168.*;<local>'
      setProxy('1', proxyIp, ignoreIp).then()

      const proxy = Proxy()
      proxy.onRequest(async (ctx, callback) => {
        if (/hk4e-api([^.]{2,10})?\.(mihoyo|hoyoverse)\.com/.test(ctx.clientToProxyRequest.headers.host)) {
          await setProxy('0')
          proxy.close()

          const wishHistoryPageUrl = `https://${ctx.clientToProxyRequest.headers.host}${ctx.clientToProxyRequest.url}`

          const check = await checkUrl(wishHistoryPageUrl)
          if (check.status) {
            return resolve(wishHistoryPageUrl)
          } else {
            return reject(new Error(window.i18n.t('modules.error.url_verification_failed', { url: wishHistoryPageUrl, msg: check.msg })))
          }
        }

        return callback()
      })
      proxy.listen({ port: proxyPort })
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
