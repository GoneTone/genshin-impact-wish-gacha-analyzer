<template>
  <navbar-layout></navbar-layout>

  <div id="content-wrapper" class="d-flex flex-column">
    <div id="content">
      <nav-layout></nav-layout>

      <div class="container-fluid mt-4">
        <header-layout :title="title" :data-time-range="dataTimeRange" :update-time="updateTime"></header-layout>

        <draws-info :accumulate-draws="allCount" :accumulate-not-win-draws="drawsCountInWin" :averag-draws-count-in-win="averagDrawsCountInWin"></draws-info>

        <h4>級別中獎率</h4>
        <div class="row">
          <percentage title="5星中獎率" color="bd6932" :percentage="wins.rank.five.chance"></percentage>
          <percentage title="4星中獎率" color="a256e1" :percentage="wins.rank.four.chance"></percentage>
          <percentage title="3星中獎率" color="8e8e8e" :percentage="wins.rank.three.chance"></percentage>
        </div>

        <h4>角色武器中獎率</h4>
        <div class="row">
          <percentage title="角色中獎率" color="bd6932" :percentage="wins.characterWeapon.character.chance"></percentage>
          <percentage title="武器中獎率" color="a256e1" :percentage="wins.characterWeapon.weapon.chance"></percentage>
        </div>

        <h4>中獎數圓餅圖</h4>
        <div class="row">
          <rank-pie-chart :five-rank-wins="wins.rank.five.count" :four-rank-wins="wins.rank.four.count" :three-rank-wins="wins.rank.three.count"></rank-pie-chart>
          <character-weapon-pie-chart :character-wins="wins.characterWeapon.character.count" :weapon-wins="wins.characterWeapon.weapon.count"></character-weapon-pie-chart>
        </div>

        <h4>表格</h4>
        <div class="card shadow mb-4">
          <div class="card-header py-3">
            <h6 class="m-0 font-weight-bold text-primary">{{ title }}</h6>
          </div>
          <div class="card-body">
            <div class="table-responsive">
              <!--suppress HtmlDeprecatedAttribute -->
              <table class="table table-bordered table-hover" id="dataTable" width="100%" cellspacing="0">
                <thead class="thead-light">
                <tr>
                  <th class="align-middle">總抽數</th>
                  <th class="align-middle">名稱</th>
                  <th class="align-middle">類別</th>
                  <th class="align-middle">級別</th>
                  <th class="align-middle">抽到時間</th>
                  <th class="align-middle">保底內抽數</th>
                </tr>
                </thead>
                <tfoot class="thead-light">
                <tr>
                  <th class="align-middle">總抽數</th>
                  <th class="align-middle">名稱</th>
                  <th class="align-middle">類別</th>
                  <th class="align-middle">級別</th>
                  <th class="align-middle">抽到時間</th>
                  <th class="align-middle">保底內抽數</th>
                </tr>
                </tfoot>
                <tbody>
                <tr v-for="(data, index) of this.$store.getters.datas.gachaLogs.data[this.$route.params.key]" :key="index" :class="{'text-bd6932 table-active': Number(data.rank_type) === 5, 'text-a256e1': Number(data.rank_type) === 4, 'text-8e8e8e': Number(data.rank_type) <= 3}">
                  <td class="align-middle">{{ (index + 1) }}</td>
                  <td class="align-middle"><img :src="data.icon_url" class="img-fluid" width="35" :alt="`${data.name} - Icon`" v-if="data.icon_url && data.icon_url !== null"> {{ data.name }}</td>
                  <td class="align-middle">{{ data.item_type }}</td>
                  <td class="align-middle">{{ data.rank_type }}星</td>
                  <td class="align-middle">{{ this.formatDataTime(data.time) }}</td>
                  <td class="align-middle">{{ data.draws_count_in_win }}</td>
                </tr>
                </tbody>
              </table>
            </div>
          </div>
        </div>
      </div>
    </div>

    <footer-layout></footer-layout>
  </div>
</template>

<script>
import NavbarLayout from '@/components/NavbarLayout'
import NavLayout from '@/components/NavLayout'
import HeaderLayout from '@/components/HeaderLayout.vue'
import DrawsInfo from '@/components/DrawsInfo'
import Percentage from '@/components/Percentage'
import RankPieChart from '@/components/PieChart/RankPieChart'
import CharacterWeaponPieChart from '@/components/PieChart/CharacterWeaponPieChart'
import FooterLayout from '@/components/FooterLayout.vue'

export default {
  name: 'Gacha',
  components: {
    NavbarLayout,
    NavLayout,
    HeaderLayout,
    DrawsInfo,
    Percentage,
    RankPieChart,
    CharacterWeaponPieChart,
    FooterLayout
  },
  data () {
    return {
      title: `${this.getTitle(this.$route.params.key)} - 數據圖表`,
      updateTime: this.formatDataTime(this.$store.getters.datas.gachaLogs.updateTime),
      dataTimeRange: this.getDataTimeRange(),
      allCount: this.getAllCount(),
      drawsCountInWin: this.getDrawsCountInWin(),
      averagDrawsCountInWin: this.getAveragDrawsCountInWin(),
      wins: {
        rank: {
          five: {
            count: this.getRankCount(5),
            chance: this.getChanceOfWinByRank(5)
          },
          four: {
            count: this.getRankCount(4),
            chance: this.getChanceOfWinByRank(4)
          },
          three: {
            count: this.getRankCount(3),
            chance: this.getChanceOfWinByRank(3)
          }
        },
        characterWeapon: {
          character: {
            count: this.getCharacterCount(),
            chance: this.getChanceOfWinByCharacter()
          },
          weapon: {
            count: this.getWeaponCount(),
            chance: this.getChanceOfWinByWeapon()
          }
        }
      },
      dataTableInit: false
    }
  },
  mounted () {
    document.title = `${this.title} | ${this.$store.getters.configs.app.name}` // 更新標題
    this.$store.dispatch('playerAudioEffect', 'switch_type') // 播放音效

    const _this = this
    this.$nextTick(function () {
      (function ($) {
        'use strict'

        if (!_this.dataTableInit) {
          $('#dataTable').DataTable({
            order: [[0, 'desc']],
            language: {
              lengthMenu: '每頁顯示 _MENU_ 筆記錄',
              zeroRecords: '未找到任何結果',
              info: '第 _PAGE_ 頁 / 共 _PAGES_ 頁',
              infoEmpty: '沒有任何資料',
              infoFiltered: '(從 _MAX_ 筆記錄中篩選出)',
              search: '搜尋：',
              paginate: {
                previous: '上一頁',
                next: '下一頁'
              }
            }
          })

          _this.dataTableInit = true
        }
        // eslint-disable-next-line no-undef
      })(jQuery)
    })
  },
  methods: {
    getTitle (key) {
      const gachaTypeList = this.$store.getters.datas.gachaTypeList
      const data = gachaTypeList.find(data => data.key === key)

      return data.name
    },
    formatDataTime (dataTime, format = 'L LTS') {
      return window.moment(dataTime).format(format)
    },
    getDataTimeRange () {
      const gachaLogs = this.$store.getters.datas.gachaLogs.data
      const gachaLog = gachaLogs[this.$route.params.key]

      if (gachaLog.length <= 0) {
        return ''
      }

      const startTime = this.formatDataTime(gachaLog[0].time, 'L')
      const endTime = this.formatDataTime(gachaLog[(gachaLog.length - 1)].time, 'L')

      return `${startTime} ~ ${endTime}`
    },
    getAveragDrawsCountInWin () {
      const miHoYoApi = new window.MiHoYoApi(this.$store.getters.datas.queryStringParameters)
      const gachaLogs = this.$store.getters.datas.gachaLogs.data
      const listByRank = miHoYoApi.getListByRank(gachaLogs[this.$route.params.key], 5)

      if (listByRank.length <= 0) {
        return 0
      }

      let countInWin = 0
      let count = 0
      for (const data of listByRank) {
        countInWin += data.draws_count_in_win
        count++
      }

      if (isNaN((countInWin / count))) {
        return 0
      }

      return Math.round((countInWin / count))
    },
    getAllCount () {
      const gachaLogs = this.$store.getters.datas.gachaLogs.data
      const gachaLog = gachaLogs[this.$route.params.key]

      return gachaLog.length
    },
    getDrawsCountInWin () {
      const gachaLogs = this.$store.getters.datas.gachaLogs.data
      const gachaLog = gachaLogs[this.$route.params.key]

      const latestData = gachaLog[(gachaLog.length - 1)]

      if (gachaLog.length <= 0 || Number(latestData.rank_type) === 5) {
        return 0
      }

      return latestData.draws_count_in_win
    },
    getRankCount (rank) {
      const miHoYoApi = new window.MiHoYoApi(this.$store.getters.datas.queryStringParameters)
      const gachaLogs = this.$store.getters.datas.gachaLogs.data
      const listByRank = miHoYoApi.getListByRank(gachaLogs[this.$route.params.key], rank)

      return listByRank.length
    },
    getCharacterCount () {
      const miHoYoApi = new window.MiHoYoApi(this.$store.getters.datas.queryStringParameters)
      const gachaLogs = this.$store.getters.datas.gachaLogs.data
      const listByCharacter = miHoYoApi.getListByCharacter(gachaLogs[this.$route.params.key])

      return listByCharacter.length
    },
    getWeaponCount () {
      const miHoYoApi = new window.MiHoYoApi(this.$store.getters.datas.queryStringParameters)
      const gachaLogs = this.$store.getters.datas.gachaLogs.data
      const listByWeapon = miHoYoApi.getListByWeapon(gachaLogs[this.$route.params.key])

      return listByWeapon.length
    },
    getChanceOfWinByRank (rank) {
      if (isNaN((this.getRankCount(rank) / this.getAllCount()))) {
        return 0
      }

      return Math.round(((this.getRankCount(rank) / this.getAllCount()) * 100) * 1000) / 1000
    },
    getChanceOfWinByCharacter () {
      if (isNaN((this.getCharacterCount() / (this.getCharacterCount() + this.getWeaponCount())))) {
        return 0
      }

      return Math.round(((this.getCharacterCount() / (this.getCharacterCount() + this.getWeaponCount())) * 100) * 1000) / 1000
    },
    getChanceOfWinByWeapon () {
      if (isNaN((this.getWeaponCount() / (this.getCharacterCount() + this.getWeaponCount())))) {
        return 0
      }

      return Math.round(((this.getWeaponCount() / (this.getCharacterCount() + this.getWeaponCount())) * 100) * 1000) / 1000
    }
  }
}
</script>
