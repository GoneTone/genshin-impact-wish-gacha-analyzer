/**
 * Copyright © 2020-2021 原神資訊站 Genshin Impact Info
 * https://genshininfo.reh.tw/
 *
 * Developed by 旋風之音 GoneTone
 * https://www.facebook.com/GoneToneDY
 */

'use strict'

const promisifiedAxios = require('./promisifiedAxios')

/**
 * 檢查網址狀態碼是否是 200
 *
 * @param {string} url 網址
 * @param {boolean} isReject
 *
 * @returns {{status: boolean, msg: string}}
 */
const checkUrl = async (url, isReject = true) => {
  const axios = await promisifiedAxios(url, isReject)

  if (axios.status && axios.status === 200) {
    return {
      status: true,
      msg: axios.statusText
    }
  }

  return {
    status: false,
    msg: axios.message
  }
}

module.exports = checkUrl
