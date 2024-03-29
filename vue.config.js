const moment = require('moment')

const year = (moment().format('YYYY') === '2020') ? moment().format('YYYY') : `2020-${moment().format('YYYY')}`

module.exports = {
  pluginOptions: {
    electronBuilder: {
      nodeIntegration: false,
      preload: 'src/preload.js', // preload 檔案位置
      builderOptions: {
        appId: 'tw.reh.genshininfo.gachaanalyzer', // 應用程式 ID
        productName: 'Genshin Impact Wish Gacha Analyzer', // 專案名稱
        copyright: `Copyright © ${year} 原神資訊站 Genshin Impact Info`, // 版權
        win: { // Windows 相關設定
          icon: 'build/icons/icon.ico', // 安裝檔圖示
          target: ['nsis', 'portable', 'zip'], // 安裝、免安裝、ZIP
          extraFiles: [
            {
              from: 'certificates', // Proxy 用 SSL 憑證
              to: '.http-mitm-proxy',
              filter: ['**/*']
            }
          ] // 包含的額外檔案
        },
        linux: { // Linux 相關設定
          icon: 'build/icons'
        },
        mac: { // Mac 相關設定
          icon: 'build/icons/icon.icns'
        },
        nsis: {
          oneClick: false, // 是否一鍵安裝
          perMachine: true, // 是否為每一台機器安裝
          installerIcon: 'build/icons/icon.ico', // 安裝圖示
          uninstallerIcon: 'build/icons/icon.ico', // 卸載圖示
          installerHeaderIcon: 'build/icons/icon.ico', // 安裝頂部圖示
          allowToChangeInstallationDirectory: true, // 是否可更改安裝目錄
          createDesktopShortcut: true, // 是否建立桌面捷徑
          createStartMenuShortcut: true // 是否建立開始捷徑
        },
        publish: [
          {
            provider: 'github',
            owner: 'GoneTone',
            repo: 'genshin-impact-wish-gacha-analyzer'
          }
        ]
      }
    },
    i18n: {
      locale: 'zh_TW',
      fallbackLocale: 'zh_TW',
      localeDir: 'locales',
      enableLegacy: true,
      runtimeOnly: false,
      compositionOnly: false,
      fullInstall: true
    }
  }
}
