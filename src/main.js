/**
 * Copyright © 2020-2021 原神資訊站 Genshin Impact Info
 * https://genshininfo.reh.tw/
 *
 * Developed by 旋風之音 GoneTone
 * https://www.facebook.com/GoneToneDY
 */

import { createApp } from 'vue'
import App from './App.vue'
import router from './router'
import store from './store'
import i18n from './i18n'

window.i18n = i18n.global

createApp(App).use(i18n).use(store).use(router).mount('#wrapper')
