/**
 * Copyright © 2020-2021 原神情報站 Genshin Info
 * https://genshininfo.reh.tw/
 *
 * Developed by 旋風之音 GoneTone
 * https://www.facebook.com/GoneToneDY
 */

import { createRouter, createWebHashHistory, createWebHistory } from 'vue-router'

import Home from '../views/Home.vue'
import Gacha from '../views/Gacha.vue'
import History from '../views/History.vue'
import ContributionList from '../views/ContributionList.vue'

const routes = [
  {
    path: '/',
    name: 'Home',
    component: Home
  },
  {
    path: '/gacha/:key',
    name: 'Gacha',
    component: Gacha,
    props: true
  },
  {
    path: '/history',
    name: 'History',
    component: History
  },
  {
    path: '/contribution-list',
    name: 'ContributionList',
    component: ContributionList
  }
]

const router = createRouter({
  history: process.env.IS_ELECTRON ? createWebHashHistory() : createWebHistory(),
  routes
})

export default router
