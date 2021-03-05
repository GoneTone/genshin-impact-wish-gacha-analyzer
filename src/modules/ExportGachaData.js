/**
 * Copyright © 2020-2021 原神情報站 Genshin Info
 * https://genshininfo.reh.tw/
 *
 * Developed by 旋風之音 GoneTone
 * https://www.facebook.com/GoneToneDY
 */

'use strict'

const { remote } = require('electron')
const ExcelJS = require('exceljs')
const path = require('path')
const fs = require('fs-extra')
const moment = require('moment')

class ExportGachaData {
  /**
   * ExportGachaData constructor.
   *
   * @param {Array} gachaTypeList 所有卡池類型清單
   * @param {Array} gachaLogs 所有卡池歷史紀錄
   */
  constructor (gachaTypeList, gachaLogs) {
    this._gachaTypeList = gachaTypeList
    this._gachaLogs = gachaLogs

    this._datatime = moment().format('YYYYMMDD-HHmmss')
  }

  async xlsx () {
    const workbook = new ExcelJS.Workbook()
    for (const gachaType of this._gachaTypeList) {
      const sheet = workbook.addWorksheet(gachaType.name, {
        views: [{
          state: 'frozen',
          ySplit: 1
        }]
      })

      sheet.columns = [
        { header: '總抽數', key: 'indax', width: 8 },
        { header: '名稱', key: 'name', width: 20 },
        { header: '類別', key: 'item_type', width: 10 },
        { header: '級別', key: 'rank_type', width: 8 },
        { header: '抽到時間', key: 'time', width: 25 },
        { header: '保底內抽數', key: 'draws_count_in_win', width: 8 }
      ]

      const rows = []
      let index = 0
      for (const gachaLog of this._gachaLogs[gachaType.key]) {
        index++
        rows.push([index, gachaLog.name, gachaLog.item_type, Number(gachaLog.rank_type), gachaLog.time, gachaLog.draws_count_in_win])
      }
      sheet.addRows(rows)

      for (const r of ['A', 'B', 'C', 'D', 'E', 'F']) {
        sheet.getCell(`${r}1`).alignment = {
          wrapText: true,
          vertical: 'middle',
          horizontal: 'center'
        }

        sheet.getCell(`${r}1`).fill = {
          type: 'pattern',
          pattern: 'solid',
          fgColor: {
            argb: 'ffeaecf4'
          }
        }

        sheet.getCell(`${r}1`).font = {
          color: {
            argb: 'ff6e707e'
          },
          bold: true
        }
      }

      index = 0
      for (const gachaLog of this._gachaLogs[gachaType.key]) {
        index++
        for (const r of ['A', 'B', 'C', 'D', 'E', 'F']) {
          sheet.getCell(`${r}${index + 1}`).alignment = {
            wrapText: true,
            vertical: 'middle',
            horizontal: 'left'
          }

          if (Number(gachaLog.rank_type) === 5) {
            sheet.getCell(`${r}${index + 1}`).fill = {
              type: 'pattern',
              pattern: 'solid',
              fgColor: {
                argb: 'ffdadada'
              }
            }
          }

          let rankColor = 'ff8e8e8e'
          if (Number(gachaLog.rank_type) === 5) {
            rankColor = 'ffbd6932'
          }
          if (Number(gachaLog.rank_type) === 4) {
            rankColor = 'ffa256e1'
          }

          sheet.getCell(`${r}${index + 1}`).font = {
            color: { argb: rankColor },
            bold: (Number(gachaLog.rank_type) > 3)
          }
        }
      }
    }

    const buffer = await workbook.xlsx.writeBuffer()
    const filePath = remote.dialog.showSaveDialogSync({
      defaultPath: path.join(remote.app.getPath('downloads'), `原神卡池紀錄_${this._datatime}`),
      filters: [
        { name: 'Excel', extensions: ['xlsx'] }
      ]
    })
    if (filePath) {
      await fs.ensureFile(filePath)
      await fs.writeFile(filePath, buffer)
    }
  }
}

module.exports = ExportGachaData
