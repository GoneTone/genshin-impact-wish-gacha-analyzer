/**
 * Copyright © 2020-2021 原神情報站 Genshin Info
 * https://genshininfo.reh.tw/
 *
 * Developed by 旋風之音 GoneTone
 * https://www.facebook.com/GoneToneDY
 */

import { createStore } from 'vuex'
import i18n from '@/i18n'

export default createStore({
  state: {
    loadStatus: { // 應用程式加載狀態
      status: null,
      msg: null
    },
    audio: {
      switchType: new Audio(require('@/assets/audio/effect/switch_type.mp3')),
      switchTask: new Audio(require('@/assets/audio/effect/switch_task.mp3')),
      openWin: new Audio(require('@/assets/audio/effect/open_win.mp3')),
      closeWin: new Audio(require('@/assets/audio/effect/close_win.mp3'))
    },
    configs: {
      app: {
        name: i18n.global.t('app.name'), // 應用程式名稱
        version: window.app.getVersion(), // 應用程式版本號
        githubUrl: process.env.VUE_APP_GITHUB_URL, // 應用程式 GitHub 網址
        translationUrl: process.env.VUE_APP_TRANSLATION_URL // 應用程式協助翻譯網址
      },
      team: {
        name: process.env.VUE_APP_TEAM_NAME, // 團隊名稱
        websiteUrl: process.env.VUE_APP_TEAM_WEBSITE_URL, // 團隊網站網址
        facebookUrl: process.env.VUE_APP_TEAM_FACEBOOK_URL, // 團隊 Facebook 網址
        discordUrl: process.env.VUE_APP_TEAM_DISCORD_URL // 團隊 Discord 網址
      },
      developer: {
        displayName: process.env.VUE_APP_DEVELOPER_DISPLAY_NAME, // 開發者名稱
        url: process.env.VUE_APP_DEVELOPER_URL // 開發者網址
      },
      api: {
        mihoyo: { // 米哈遊相關 API
          host: process.env.VUE_APP_MIHOYO_API_HOST,
          path: process.env.VUE_APP_MIHOYO_API_PATH,
          getConfigList: process.env.VUE_APP_MIHOYO_API_GET_CONFIG_LIST_PATHNAME,
          getGachaLog: process.env.VUE_APP_MIHOYO_API_GET_GACHA_LOG_PATHNAME,
          web: {
            host: process.env.VUE_APP_MIHOYO_WEBAPI_HOST,
            path: process.env.VUE_APP_MIHOYO_WEBAPI_PATH
          },
          bbs: {
            host: process.env.VUE_APP_MIHOYO_BBSAPI_HOST,
            pathIcon: process.env.VUE_APP_MIHOYO_BBSAPI_ICON_PATH
          }
        }
      },
      game: {
        guaranteedCount: process.env.VUE_APP_GAME_GACHA_GUARANTEED_COUNT,
        guaranteedCountForWeapon: process.env.VUE_APP_GAME_GACHA_GUARANTEED_COUNT_FOR_WEAPON
      },
      randomStr: null
    },
    datas: {
      playerUID: null, // 玩家 UID
      wishHistoryPageUrl: null, // 卡池歷史紀錄頁面網址
      queryStringParameters: null, // 卡池歷史紀錄頁面網址參數
      gachaTypeList: null, // 卡池類型清單
      gachaLogs: { // 卡池歷史紀錄
        update_time: null,
        data: null
      }
    },
    langNames: null
  },
  mutations: {
    setLoadStatus (state, loadStatus) {
      state.loadStatus = loadStatus
    },
    setDatas (state, datas) {
      state.datas = datas
    },
    setLangNames (state, langNames) {
      state.langNames = langNames
    },
    setRandomStr (state, randomStr) {
      state.configs.randomStr = randomStr
    }
  },
  actions: {
    async setDatas (context, updateGachaLog = false) {
      try {
        const readGenshinFile = new window.ReadGenshinFile()
        const wishHistoryPageUrl = await readGenshinFile.getWishHistoryPageUrl()
        const parseUrl = new URL(wishHistoryPageUrl)
        const searchParams = parseUrl.searchParams
        const queryStringParameters = {
          authkey_ver: searchParams.get('authkey_ver') ?? '',
          sign_type: searchParams.get('sign_type') ?? '',
          auth_appid: searchParams.get('auth_appid') ?? '',
          init_type: searchParams.get('init_type') ?? '',
          gacha_id: searchParams.get('gacha_id') ?? '',
          lang: searchParams.get('lang') ?? '',
          device_type: searchParams.get('device_type') ?? '',
          ext: searchParams.get('ext') ?? '',
          game_version: searchParams.get('game_version') ?? '',
          region: searchParams.get('region') ?? '',
          authkey: searchParams.get('authkey') ?? '',
          game_biz: searchParams.get('game_biz') ?? '',
          end_id: searchParams.get('end_id') ?? '0'
        }

        const miHoYoApi = new window.MiHoYoApi(queryStringParameters)
        const fileControl = new window.FileControl(window.app.getPath('userData'))

        const isVersionMatch = await fileControl.isVersionMatch()
        if (!isVersionMatch) {
          updateGachaLog = true
        }

        window.log.info('Loading gacha data...')

        context.commit('setLoadStatus', {
          status: 'load',
          msg: i18n.global.t('ui.text.loading.loading_gacha_data', { may_take_a_while: `<span class="text-danger">${i18n.global.t('ui.text.loading.may_take_a_while')}</span>` })
        })

        const playerUID = await miHoYoApi.getPlayerUID(updateGachaLog)

        window.log.info(`Reading UID "${playerUID}" player gacha history data...`)

        const gachaTypeList = await miHoYoApi.getGachaTypeList()
        const gachaLogs = []
        let updateTime
        for (const data of gachaTypeList) {
          window.log.info(`Reading "${data.name}" gacha history data...`)

          context.commit('setLoadStatus', {
            status: 'load',
            msg: i18n.global.t('ui.text.loading.loading_gacha_data_uid', { uid: `<kbd>${playerUID}</kbd>`, gacha_name: `<span class="text-info">${data.name}</span>`, may_take_a_while: `<span class="text-danger">${i18n.global.t('ui.text.loading.may_take_a_while')}</span>` })
          })

          gachaLogs[data.key] = await miHoYoApi.getGachaLog(data.key, 20, playerUID, updateGachaLog)
          updateTime = await miHoYoApi.getUpdateTime()
        }

        context.commit('setDatas', {
          playerUID: playerUID,
          wishHistoryPageUrl: wishHistoryPageUrl,
          queryStringParameters: queryStringParameters,
          gachaTypeList: gachaTypeList,
          gachaLogs: {
            updateTime: updateTime,
            data: gachaLogs
          }
        })

        window.log.info('Gacha history data has been read.')

        console.log(this.getters.datas.queryStringParameters)
        console.log(this.getters.datas.gachaTypeList)
        console.log(this.getters.datas.gachaLogs)

        context.commit('setLoadStatus', {
          status: true,
          msg: 'Success.'
        })
      } catch (e) {
        window.log.error(e.message)

        context.commit('setLoadStatus', {
          status: false,
          msg: e.message
        })
      }
    },
    async playerAudioEffect (context, name) {
      switch (name) {
        case 'switch_type':
          context.state.audio.switchType.pause()
          context.state.audio.switchType.currentTime = 0
          await context.state.audio.switchType.play()

          break
        case 'switch_task':
          context.state.audio.switchTask.pause()
          context.state.audio.switchTask.currentTime = 0
          await context.state.audio.switchTask.play()

          break
        case 'open_win':
          context.state.audio.openWin.pause()
          context.state.audio.openWin.currentTime = 0
          await context.state.audio.openWin.play()

          break
        case 'close_win':
          context.state.audio.closeWin.pause()
          context.state.audio.closeWin.currentTime = 0
          await context.state.audio.closeWin.play()

          break
      }
    },
    async setLangNames (context) {
      const fileControl = new window.FileControl(window.app.getPath('userData'))

      const langNames = {}
      for (const locale of i18n.global.availableLocales) {
        langNames[locale] = fileControl.getLangNames(locale)
      }

      i18n.global.locale = await fileControl.readLangCode() // 切換成上次使用的語言
      window.log.info(`Set language to ${i18n.global.locale}.`)

      context.commit('setLangNames', langNames)
    },
    generateRandomStr (context) {
      const possible = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'

      let text = ''
      for (let i = 0; i < 10; i++) {
        text += possible.charAt(Math.floor(Math.random() * possible.length))
      }

      context.commit('setRandomStr', text)
    }
  },
  getters: {
    loadStatus (state) {
      return state.loadStatus
    },
    configs (state) {
      return state.configs
    },
    datas (state) {
      return state.datas
    },
    langNames (state) {
      return state.langNames
    },
    randomStr (state) {
      return state.configs.randomStr
    }
  }
})
