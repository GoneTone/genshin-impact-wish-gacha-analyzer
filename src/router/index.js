/**
 * Copyright © 2020-2021 原神資訊站 Genshin Impact Info
 * https://genshininfo.reh.tw/
 *
 * Developed by 旋風之音 GoneTone
 * https://www.facebook.com/GoneToneDY
 */

import { createRouter, createWebHashHistory, createWebHistory } from 'vue-router'

import Home from '../views/Home.vue'
import Gacha from '../views/Gacha.vue'
import Page from '../views/Page.vue'
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
    path: '/page/:url',
    name: 'Page',
    component: Page,
    props: true
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
