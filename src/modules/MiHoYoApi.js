/**
 * Copyright © 2020-2021 原神資訊站 Genshin Impact Info
 * https://genshininfo.reh.tw/
 *
 * Developed by 旋風之音 GoneTone
 * https://www.facebook.com/GoneToneDY
 */

'use strict'

const { remote } = require('electron')
const log = require('electron-log')
const checkUrl = require('@/modules/checkUrl')
const promisifiedAxios = require('@/modules/promisifiedAxios')
const FileControl = require('@/modules/FileControl')
const ReadGenshinFile = require('@/modules/ReadGenshinFile')

class MiHoYoApi {
  /**
   * MiHoYoApi constructor.
   *
   * @param {Object} queryStringParameters 網址參數
   */
  constructor (queryStringParameters) {
    this._mihoyoApiHost = process.env.VUE_APP_MIHOYO_API_HOST
    this._mihoyoWebApiHost = process.env.VUE_APP_MIHOYO_WEBAPI_HOST
    this._mihoyoBbsApiHost = process.env.VUE_APP_MIHOYO_BBSAPI_HOST
    this._mihoyoSeaHost = process.env.VUE_APP_MIHOYO_SEA_HOST
    this._mihoyoActHost = process.env.VUE_APP_HOYOLAB_ACT_HOST
    this._mihoyoApiPath = process.env.VUE_APP_MIHOYO_API_PATH
    this._mihoyoWebApiPath = process.env.VUE_APP_MIHOYO_WEBAPI_PATH
    this._mihoyoBbsApiIconPath = process.env.VUE_APP_MIHOYO_BBSAPI_ICON_PATH
    this._mihoyoApiGetConfigListPathName = process.env.VUE_APP_MIHOYO_API_GET_CONFIG_LIST_PATHNAME
    this._mihoyoApiGetGachaLogPathName = process.env.VUE_APP_MIHOYO_API_GET_GACHA_LOG_PATHNAME
    this._mihoyoApiGachaCharacterTypeNames = process.env.VUE_APP_MIHOYO_API_GACHA_CHARACTER_TYPE_NAMES.split(',')
    this._mihoyoApiGachaWeaponTypeNames = process.env.VUE_APP_MIHOYO_API_GACHA_WEAPON_TYPE_NAMES.split(',')

    this._playerUID = null

    this.configListApiUrlCheck = false
    this.gachaLogApiUrlCheck = false
    this.itemsApiUrlCheck = false

    this._queryStringParameters = queryStringParameters

    this._basePath = remote.app.getPath('userData')
    this._fileControl = new FileControl(this._basePath)
    this._readGenshinFile = new ReadGenshinFile()

    this._characterList = []
    this._weaponList = []
  }

  /**
   * 取得卡池類型資料 Api 網址
   *
   * @returns {Promise<string>}
   */
  async getConfigListApiUrl () {
    const apiUrlAppend = new URL(`https://${this._mihoyoApiHost}${this._mihoyoApiPath}${this._mihoyoApiGetConfigListPathName}`)
    apiUrlAppend.searchParams.append('authkey_ver', this._queryStringParameters.authkey_ver.toString())
    apiUrlAppend.searchParams.append('sign_type', this._queryStringParameters.sign_type.toString())
    apiUrlAppend.searchParams.append('auth_appid', this._queryStringParameters.auth_appid.toString())
    apiUrlAppend.searchParams.append('lang', this._queryStringParameters.lang.toString())
    apiUrlAppend.searchParams.append('game_version', this._queryStringParameters.game_version.toString())
    apiUrlAppend.searchParams.append('region', this._queryStringParameters.region.toString())
    apiUrlAppend.searchParams.append('authkey', this._queryStringParameters.authkey.toString())
    apiUrlAppend.searchParams.append('game_biz', this._queryStringParameters.game_biz.toString())

    const apiUrl = apiUrlAppend.href

    if (!this.configListApiUrlCheck) {
      const check = await checkUrl(apiUrl)
      if (check.status) {
        this.configListApiUrlCheck = true
        return apiUrl
      } else {
        throw Error(window.i18n.t('modules.error.get_gacha_type_data_api_url_failed'))
      }
    } else {
      return apiUrl
    }
  }

  /**
   * 取得卡池歷史紀錄 Api 網址
   *
   * @param {number} gachaTypeID 卡池類型 ID
   * @param {number} page 頁數
   * @param {number} size 一頁資料最大數 (最大 20，預設 6)
   * @param {String} endID (預設 '0')
   *
   * @returns {Promise<string>}
   */
  async getGachaLogApiUrl (gachaTypeID, page, size = 6, endID = '0') {
    size = (size > 20) ? 20 : (size < 1) ? 1 : size

    const apiUrlAppend = new URL(`https://${this._mihoyoApiHost}${this._mihoyoApiPath}${this._mihoyoApiGetGachaLogPathName}`)
    apiUrlAppend.searchParams.append('authkey_ver', this._queryStringParameters.authkey_ver.toString())
    apiUrlAppend.searchParams.append('sign_type', this._queryStringParameters.sign_type.toString())
    apiUrlAppend.searchParams.append('auth_appid', this._queryStringParameters.auth_appid.toString())
    apiUrlAppend.searchParams.append('init_type', gachaTypeID.toString())
    apiUrlAppend.searchParams.append('gacha_id', this._queryStringParameters.gacha_id.toString())
    apiUrlAppend.searchParams.append('lang', this._queryStringParameters.lang.toString())
    apiUrlAppend.searchParams.append('device_type', this._queryStringParameters.device_type.toString())
    apiUrlAppend.searchParams.append('game_version', this._queryStringParameters.game_version.toString())
    apiUrlAppend.searchParams.append('plat_type', this._queryStringParameters.plat_type.toString())
    apiUrlAppend.searchParams.append('region', this._queryStringParameters.region.toString())
    apiUrlAppend.searchParams.append('authkey', this._queryStringParameters.authkey.toString())
    apiUrlAppend.searchParams.append('game_biz', this._queryStringParameters.game_biz.toString())
    apiUrlAppend.searchParams.append('gacha_type', gachaTypeID.toString())
    apiUrlAppend.searchParams.append('page', page.toString())
    apiUrlAppend.searchParams.append('size', size.toString())
    apiUrlAppend.searchParams.append('end_id', endID)

    const apiUrl = apiUrlAppend.href

    if (!this.gachaLogApiUrlCheck) {
      const check = await checkUrl(apiUrl)
      if (check.status) {
        this.gachaLogApiUrlCheck = true
        return apiUrl
      } else {
        throw Error(window.i18n.t('modules.error.get_gacha_history_api_url_failed'))
      }
    } else {
      return apiUrl
    }
  }

  /**
   * 取得項目資料 Api 網址
   *
   * @param {String} lang 語言代碼
   *
   * @returns {Promise<string>}
   */
  async getItemsApiUrl (lang) {
    if (this._queryStringParameters.region.toString()) {
      const apiUrlAppend = new URL(`https://${this._mihoyoWebApiHost}${this._mihoyoWebApiPath}${this._queryStringParameters.region.toString()}/items/${lang}.json`)
      const apiUrl = apiUrlAppend.href

      if (!this.itemsApiUrlCheck) {
        const check = await checkUrl(apiUrl)
        if (check.status) {
          this.itemsApiUrlCheck = true
          return apiUrl
        } else {
          throw Error(window.i18n.t('modules.error.get_items_api_url_failed'))
        }
      } else {
        return apiUrl
      }
    } else {
      throw Error(window.i18n.t('modules.error.get_area_parameter_failed'))
    }
  }

  /**
   * 驗證返回狀態碼
   *
   * @param {Number} retcode 返回狀態碼
   *
   * @returns {boolean}
   */
  verificationRetcode (retcode) {
    switch (retcode) {
      case 0:
        return true
      case -100:
        throw Error(window.i18n.t('modules.error.mihoyo_api_invalid'))
      case -101:
        throw Error(window.i18n.t('modules.error.mihoyo_api_expired'))
      default:
        return false
    }
  }

  /**
   * 取得卡池類型清單
   *
   * @returns {Promise<Array>}
   */
  async getGachaTypeList () {
    try {
      const configListApiUrl = await this.getConfigListApiUrl()
      const axios = await promisifiedAxios(configListApiUrl)
      const data = axios.data

      if (this.verificationRetcode(data.retcode)) {
        return data.data.gacha_type_list
      } else {
        log.error(`Get gacha type list failed: ${configListApiUrl} (${data.retcode} ${data.message})`)
      }
    } catch (e) {
      throw Error(e.message)
    }

    throw Error(window.i18n.t('modules.error.get_gacha_type_list_failed'))
  }

  /**
   * 取得卡池歷史紀錄
   *
   * @param {Number} gachaTypeID 卡池類型 ID
   * @param {Number} size 一頁資料最大數 (最大 20，預設 6)
   * @param {String} playerUID 玩家 UID
   * @param {boolean} update 是否更新資料 (預設 false)
   *
   * @returns {Promise<Array>}
   */
  async getGachaLog (gachaTypeID, size = 6, playerUID, update = false) {
    let logArray = []
    let page = 1
    let message = null

    const isExists = await this._fileControl.isExists(`${this._basePath}/data/${playerUID}/gacha/${gachaTypeID}.json`)
    if (!isExists || update) {
      try {
        size = (size > 20) ? 20 : (size < 1) ? 1 : size

        let endID = '0'
        while (true) {
          const gachaLogApiUrl = await this.getGachaLogApiUrl(gachaTypeID, page, size, endID)
          const axios = await promisifiedAxios(gachaLogApiUrl)
          const data = axios.data

          if (this.verificationRetcode(data.retcode)) {
            if (data.data.list.length > 0) {
              const res = data.data.list

              endID = res[res.length - 1].id

              logArray = logArray.concat(res)
              page++

              await new Promise((resolve) => setTimeout(resolve, 400)) // 應付 miHoYo API 限速，每 400ms 發送一次 HTTP 請求
            } else {
              break
            }
          } else {
            message = window.i18n.t('modules.error.get_gacha_history_failed')
            log.error(`Get gacha history failed: ${gachaLogApiUrl} (${data.retcode} ${data.message})`)

            break
          }
        }
      } catch (e) {
        throw Error(e.message)
      }

      if (message !== null) {
        throw Error(message)
      }

      const character = new window.hoyowikiApi.Character()
      const weapon = new window.hoyowikiApi.Weapon()

      const newLogArray = []
      let drawsCountInWin = 1
      let hoyowikiApiIsSetLanguage = false
      for (const data of logArray.reverse()) {
        if (!hoyowikiApiIsSetLanguage) {
          await window.hoyowikiApi.setLanguage(data.lang)
          hoyowikiApiIsSetLanguage = true
        }

        const characterList = this._characterList.length > 0 ? this._characterList : await character.getList()
        const weaponList = this._weaponList.length > 0 ? this._weaponList : await weapon.getList()
        this._characterList = characterList
        this._weaponList = weaponList

        data.draws_count_in_win = drawsCountInWin

        if (this.isCharacter(data.item_type)) {
          const characterData = characterList.filter(character => character.name === data.name)[0]
          if (characterData) {
            const characterId = Number(characterData.entry_page_id)
            const entry = new window.hoyowikiApi.Entry()
            const character = await entry.get(characterId)

            data.icon_url = character.icon_url
            data.image_url = character.header_img_url
            data.hoyowiki_url = `https://wiki.hoyolab.com/pc/genshin/entry/${characterId.toString()}`
          } else {
            data.icon_url = null
            data.image_url = null
            data.hoyowiki_url = null
          }
        } else if (this.isWeapon(data.item_type)) {
          const weaponData = weaponList.filter(weapon => weapon.name === data.name)[0]
          if (weaponData) {
            const weaponId = Number(weaponData.entry_page_id)
            const entry = new window.hoyowikiApi.Entry()
            const weapon = await entry.get(weaponId)

            data.icon_url = weapon.icon_url
            data.image_url = null
            data.hoyowiki_url = `https://wiki.hoyolab.com/pc/genshin/entry/${weaponId.toString()}`
          } else {
            data.icon_url = null
            data.image_url = null
            data.hoyowiki_url = null
          }
        } else {
          data.icon_url = null
          data.image_url = null
          data.hoyowiki_url = null
        }

        if (Number(data.rank_type) === 5) {
          drawsCountInWin = 0
        }

        drawsCountInWin++

        newLogArray.push(data)
      }

      await this._fileControl.writeGachaData(`/data/${playerUID}/gacha/`, gachaTypeID.toString(), newLogArray.reverse())
    }

    const gachaData = await this._fileControl.readGachaData(`/data/${playerUID}/gacha/`, gachaTypeID.toString())
    return gachaData.reverse()
  }

  /**
   * 取得項目資料
   *
   * @param {String} lang 語言代碼
   *
   * @returns {Promise<Array>}
   */
  async getItems (lang) {
    try {
      const itemsApiUrl = await this.getItemsApiUrl(lang)
      const axios = await promisifiedAxios(itemsApiUrl)

      return axios.data
    } catch (e) {
      throw Error(e.message)
    }
  }

  /**
   * 取得更新時間
   *
   * @returns {Promise<string>}
   */
  async getUpdateTime () {
    try {
      const uid = await this.getPlayerUID()
      return await this._fileControl.readUpdateTime(`/data/${uid}/gacha/`)
    } catch (e) {
      throw Error(e.message)
    }
  }

  /**
   * 取得指定級別的清單
   *
   * @param {Array} gachaLog 卡池歷史紀錄
   * @param {Number} rank 級別
   *
   * @returns {Array}
   */
  getListByRank (gachaLog, rank) {
    if (rank <= 3) {
      return gachaLog.filter(data => Number(data.rank_type) <= rank)
    }

    return gachaLog.filter(data => Number(data.rank_type) === rank)
  }

  /**
   * 取得角色清單
   *
   * @param {Array} gachaLog 卡池歷史紀錄
   *
   * @returns {Array}
   */
  getListByCharacter (gachaLog) {
    return gachaLog.filter(data => this.isCharacter(data.item_type))
  }

  /**
   * 取得武器清單
   *
   * @param {Array} gachaLog 卡池歷史紀錄
   *
   * @returns {Array}
   */
  getListByWeapon (gachaLog) {
    return gachaLog.filter(data => this.isWeapon(data.item_type))
  }

  /**
   * 是否為角色
   *
   * @param {String} itemTypeName 項目類型名稱
   *
   * @returns {boolean}
   */
  isCharacter (itemTypeName) {
    const characterTypeNames = new Set(this._mihoyoApiGachaCharacterTypeNames)
    return characterTypeNames.has(itemTypeName)
  }

  /**
   * 是否為武器
   *
   * @param {String} itemTypeName 項目類型名稱
   *
   * @returns {boolean}
   */
  isWeapon (itemTypeName) {
    const weaponTypeNames = new Set(this._mihoyoApiGachaWeaponTypeNames)
    return weaponTypeNames.has(itemTypeName)
  }

  /**
   * 取得項目 ID
   *
   * @param {Object} data 項目資料
   *
   * @returns {String|Boolean}
   */
  async getItemID (data) {
    const items = await this.getItems(data.lang)
    const itemData = items.find(itemData => itemData.name === data.name)

    if (itemData === undefined) {
      return false
    }

    return itemData.item_id
  }

  /**
   * 取得原神 Icon 網址
   *
   * @param {String} id 項目 ID
   *
   * @returns {String|boolean}
   */
  async getGenshinIconUrl (id) {
    const items = await this.getItems('en-us')
    const data = items.find(data => data.item_id === id)

    let path = null
    if (this.isCharacter(data.item_type)) {
      path = 'character_icon/UI_AvatarIcon_'
    }
    /*
    if (this.isWeapon(data.item_type)) {
      path = 'equip/UI_EquipIcon_'
    }
    */

    if (path !== null) {
      const iconName = this.genshinIconNameReplace(data.name.replace(/\s+/g, '_'))
      return `https://${this._mihoyoBbsApiHost}${this._mihoyoBbsApiIconPath}${path}${iconName}.png`
    }

    return false
  }

  /**
   * 取得原神角色圖像網址
   *
   * @param {String} id 項目 ID
   *
   * @returns {String|boolean}
   */
  async getGenshinCharacterImageUrl (id) {
    const items = await this.getItems('en-us')
    const data = items.find(data => data.item_id === id)

    let path = null
    if (this.isCharacter(data.item_type)) {
      path = 'character_image/UI_AvatarIcon_'
    }

    if (path !== null) {
      const iconName = this.genshinIconNameReplace(data.name.replace(/\s+/g, '_'))
      return `https://${this._mihoyoBbsApiHost}${this._mihoyoBbsApiIconPath}${path}${iconName}@2x.png`
    }

    return false
  }

  /**
   * 原神 Icon 名稱替換
   *
   * @param {String} iconName Icon 名稱
   *
   * @returns {String}
   */
  genshinIconNameReplace (iconName) {
    const replaceList = require('@/assets/datas/icon_name_replace_list.json')
    return (replaceList[iconName] !== undefined) ? replaceList[iconName] : iconName
  }

  /**
   * 取得玩家 UID
   *
   * @param {boolean} updateUID 是否更新 UID (預設 false)
   *
   * @returns {Promise<string>}
   */
  async getPlayerUID (updateUID = false) {
    let playerUID
    if (this._playerUID === null || updateUID) {
      const gachaTypeList = await this.getGachaTypeList()
      for (const gachaTypeData of gachaTypeList) {
        const gachaLogApiUrl = await this.getGachaLogApiUrl(gachaTypeData.key, 1, 1)
        const axios = await promisifiedAxios(gachaLogApiUrl)
        const data = axios.data

        if (this.verificationRetcode(data.retcode)) {
          if (data.data.list.length > 0) {
            playerUID = data.data.list[0].uid
            break
          }
        } else {
          log.error(`Get gacha history failed: ${gachaLogApiUrl} (${data.retcode} ${data.message})`)
          break
        }
      }

      if (playerUID === null) {
        try {
          playerUID = await this._readGenshinFile.getPlayerUID()
        } catch (e) {
          throw Error(e.message)
        }
      }

      this._playerUID = playerUID
    } else {
      playerUID = this._playerUID
    }

    return playerUID
  }

  /**
   * 取得簽到頁面網址
   *
   * @returns {string}
   */
  getSigninPageUrl () {
    const actId = 'e202102251931481'
    const path = '/ys/event/signin-sea-v3/index.html'

    const pageUrlAppend = new URL(`https://${this._mihoyoActHost}${path}`)
    pageUrlAppend.searchParams.append('act_id', actId.toString())

    return pageUrlAppend.href
  }
}

module.exports = MiHoYoApi
