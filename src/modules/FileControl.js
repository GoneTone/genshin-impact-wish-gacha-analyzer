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
const moment = require('moment')

class FileControl {
  /**
   * JsonFileControl constructor.
   *
   * @param {String} basePath 基於路徑
   */
  constructor (basePath) {
    this.basePath = basePath
  }

  /**
   * 從本地 Json 檔案讀取卡池歷史紀錄
   *
   * @param {String} path 資料夾路徑
   * @param {String} fileName 檔案名稱
   * @returns {Promise<Array>}
   */
  async readGachaData (path, fileName) {
    try {
      const data = await fs.promises.readFile(`${this.basePath}${path}${fileName}.json`, 'utf-8')
      return JSON.parse(data.toString())
    } catch (e) {
      throw Error(e.message)
    }
  }

  /**
   * 將卡池歷史紀錄寫入本地 Json 檔案
   *
   * @param {String} path 資料夾路徑
   * @param {String} fileName 檔案名稱
   * @param {Array} data 歷史紀錄資料
   */
  async writeGachaData (path, fileName, data) {
    const fullPath = `${this.basePath}${path}`

    try {
      const isExists = await this.isExists(fullPath)
      if (!isExists) {
        await fs.promises.mkdir(fullPath, {
          recursive: true
        })
      }

      await fs.promises.writeFile(`${fullPath}${fileName}.json`, JSON.stringify(data))
      await this.writeUpdateTime(path)
    } catch (e) {
      throw Error(e.message)
    }
  }

  /**
   * 讀取更新時間
   *
   * @param {String} path 資料夾路徑
   *
   * @returns {Promise<string>}
   */
  async readUpdateTime (path) {
    const fullPath = `${this.basePath}${path}`

    try {
      const data = await fs.promises.readFile(`${fullPath}update_time.txt`, 'utf-8')
      return data.toString()
    } catch (e) {
      throw Error(e.message)
    }
  }

  /**
   * 寫入更新時間
   *
   * @param {String} path 資料夾路徑
   */
  async writeUpdateTime (path) {
    const fullPath = `${this.basePath}${path}`

    try {
      const isExists = await this.isExists(fullPath)
      if (!isExists) {
        await fs.promises.mkdir(fullPath, {
          recursive: true
        })
      }

      await fs.promises.writeFile(`${fullPath}update_time.txt`, moment().format())
    } catch (e) {
      throw Error(e.message)
    }
  }

  /**
   * 讀取本地版本號
   *
   * @returns {Promise<string|boolean>}
   */
  async readLocalVersion () {
    const filePath = `${this.basePath}/version.txt`

    try {
      const isExists = await this.isExists(filePath)
      if (isExists) {
        const data = await fs.promises.readFile(filePath, 'utf-8')
        return data.toString()
      }

      return false
    } catch (e) {
      return false
    }
  }

  /**
   * 寫入版本號
   */
  async writeVersion () {
    try {
      const isExists = await this.isExists(this.basePath)
      if (!isExists) {
        await fs.promises.mkdir(this.basePath, {
          recursive: true
        })
      }

      await fs.promises.writeFile(`${this.basePath}/version.txt`, remote.app.getVersion())
    } catch (e) {
      throw Error(e.message)
    }
  }

  /**
   * 版本是否相符
   *
   * @returns {Promise<boolean>}
   */
  async isVersionMatch () {
    const localVersion = await this.readLocalVersion()
    if (localVersion !== false && localVersion === remote.app.getVersion()) {
      return true
    }

    await this.writeVersion()
    return false
  }

  /**
   * 取得語言名稱
   *
   * @param {String} locale 語言代碼
   *
   * @returns {String}
   */
  getLangNames (locale) {
    const langData = require(`@/locales/${locale}.json`)

    if (langData['lang.name'] !== undefined && langData['lang.name'] === '繁體中文' && locale !== 'zh_TW') return locale

    return (langData['lang.name'] === undefined || langData['lang.name'] === '') ? locale : langData['lang.name']
  }

  /**
   * 讀取語言代碼
   *
   * @returns {Promise<string|boolean>}
   */
  async readLangCode () {
    const filePath = `${this.basePath}/lang_code.txt`

    try {
      const isExists = await this.isExists(filePath)
      if (isExists) {
        const data = await fs.promises.readFile(filePath, 'utf-8')
        return data.toString()
      }

      return remote.app.getLocale().replace('-', '_')
    } catch (e) {
      return remote.app.getLocale().replace('-', '_')
    }
  }

  /**
   * 寫入語言代碼
   *
   * @param {String} langCode 語言代碼
   */
  async writeLangCode (langCode) {
    try {
      const isExists = await this.isExists(this.basePath)
      if (!isExists) {
        await fs.promises.mkdir(this.basePath, {
          recursive: true
        })
      }

      await fs.promises.writeFile(`${this.basePath}/lang_code.txt`, langCode)
    } catch (e) {
      throw Error(e.message)
    }
  }

  /**
   * 檔案或資料夾是否存在
   *
   * @param {String} path 路徑
   *
   * @returns {Promise<boolean>}
   */
  async isExists (path) {
    let isExists
    try {
      await fs.promises.stat(path)
      isExists = true
    } catch (e) {
      isExists = false
    }

    return isExists
  }
}

module.exports = FileControl
