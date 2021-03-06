/**
 * Copyright © 2020-2021 原神情報站 Genshin Info
 * https://genshininfo.reh.tw/
 *
 * Developed by 旋風之音 GoneTone
 * https://www.facebook.com/GoneToneDY
 */

import { createStore } from 'vuex'

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
        name: process.env.VUE_APP_NAME, // 應用程式名稱
        version: window.app.getVersion(), // 應用程式版本號
        githubUrl: process.env.VUE_APP_GITHUB_URL // 應用程式 GitHub 網址
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
        guaranteedCount: process.env.VUE_APP_GAME_GACHA_GUARANTEED_COUNT
      }
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
    }
  },
  mutations: {
    setLoadStatus (state, loadStatus) {
      state.loadStatus = loadStatus
    },
    setDatas (state, datas) {
      state.datas = datas
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
          game_biz: searchParams.get('game_biz') ?? ''
        }

        const miHoYoApi = new window.MiHoYoApi(queryStringParameters)
        const fileControl = new window.FileControl(window.app.getPath('userData'))

        const isVersionMatch = await fileControl.isVersionMatch()
        if (!isVersionMatch) {
          updateGachaLog = true
        }

        window.log.info('加載卡池資料...')

        context.commit('setLoadStatus', {
          status: 'load',
          msg: '正在加載卡池資料，<span class="text-danger">可能需要一點時間</span>...'
        })

        const uid = await miHoYoApi.getPlayerUID()

        window.log.info(`讀取 UID "${uid}" 玩家的卡池歷史資料...`)

        const gachaTypeList = await miHoYoApi.getGachaTypeList()
        const gachaLogs = []
        let updateTime
        for (const data of gachaTypeList) {
          window.log.info(`讀取 "${data.name}" 卡池歷史資料...`)

          context.commit('setLoadStatus', {
            status: 'load',
            msg: `正在讀取 UID <kbd>${uid}</kbd> 玩家的 <span class="text-info">${data.name}</span> 卡池歷史資料，<span class="text-danger">可能需要一點時間</span>...`
          })

          gachaLogs[data.key] = await miHoYoApi.getGachaLog(data.key, 20, updateGachaLog)
          updateTime = await miHoYoApi.getUpdateTime()
        }

        context.commit('setDatas', {
          playerUID: uid,
          wishHistoryPageUrl: wishHistoryPageUrl,
          queryStringParameters: queryStringParameters,
          gachaTypeList: gachaTypeList,
          gachaLogs: {
            updateTime: updateTime,
            data: gachaLogs
          }
        })

        window.log.info('卡池歷史資料讀取完畢。')

        console.log(this.getters.datas.gachaTypeList)
        console.log(this.getters.datas.gachaLogs)

        context.commit('setLoadStatus', {
          status: true,
          msg: 'Success.'
        })
      } catch (e) {
        window.error.info(e.message)

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
    }
  }
})
