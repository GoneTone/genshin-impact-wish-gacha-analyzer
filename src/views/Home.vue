<template>
  <navbar-layout></navbar-layout>

  <div id="content-wrapper" class="d-flex flex-column">
    <div id="content">
      <nav-layout></nav-layout>

      <div class="container-fluid mt-4">
        <header-layout :title="title" :update-time="updateTime"></header-layout>

        <draws-info :accumulate-draws="allCount" :averag-draws-count-in-win="averagDrawsCountInWin" is-no-display-guaranteed></draws-info>

        <h4>{{ $t("ui.text.chance_of_win_by_rank") }}</h4>
        <div class="row">
          <percentage :title="$t('ui.text.chance_of_win_by_five_rank')" color="bd6932" :percentage="wins.rank.five.chance"></percentage>
          <percentage :title="$t('ui.text.chance_of_win_by_four_rank')" color="a256e1" :percentage="wins.rank.four.chance"></percentage>
          <percentage :title="$t('ui.text.chance_of_win_by_three_rank')" color="8e8e8e" :percentage="wins.rank.three.chance"></percentage>
        </div>

        <h4>{{ $t("ui.text.chance_of_win_by_character_and_weapon") }}</h4>
        <div class="row">
          <percentage :title="$t('ui.text.chance_of_win_by_character')" color="bd6932" :percentage="wins.characterWeapon.character.chance"></percentage>
          <percentage :title="$t('ui.text.chance_of_win_by_weapon')" color="a256e1" :percentage="wins.characterWeapon.weapon.chance"></percentage>
        </div>

        <h4>{{ $t("ui.text.wins_pie_chart") }}</h4>
        <div class="row">
          <rank-pie-chart :five-rank-wins="wins.rank.five.count" :four-rank-wins="wins.rank.four.count" :three-rank-wins="wins.rank.three.count"></rank-pie-chart>
          <character-weapon-pie-chart :character-wins="wins.characterWeapon.character.count" :weapon-wins="wins.characterWeapon.weapon.count"></character-weapon-pie-chart>
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
  name: 'Home',
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
  mounted () {
    window.titlebar.updateTitle(`${this.title} | ${this.$store.getters.configs.app.name}`) // 更新標題
  },
  data () {
    return {
      title: this.$t('ui.text.title.home'),
      updateTime: this.formatDataTime(this.$store.getters.datas.gachaLogs.updateTime),
      allCount: this.getAllCount(),
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
      }
    }
  },
  methods: {
    formatDataTime (dataTime, format = 'L LTS') {
      return window.moment(dataTime).format(format)
    },
    getAveragDrawsCountInWin () {
      const miHoYoApi = new window.MiHoYoApi(this.$store.getters.datas.queryStringParameters)
      const gachaTypeList = this.$store.getters.datas.gachaTypeList
      const gachaLogs = this.$store.getters.datas.gachaLogs.data

      let countInWin = 0
      let count = 0
      for (const gachaType of gachaTypeList) {
        const listByRank = miHoYoApi.getListByRank(gachaLogs[gachaType.key], 5)

        if (listByRank.length > 0) {
          for (const data of listByRank) {
            countInWin += data.draws_count_in_win
            count++
          }
        }
      }

      if (isNaN((countInWin / count))) {
        return 0
      }

      return Math.round((countInWin / count))
    },
    getAllCount () {
      const gachaTypeList = this.$store.getters.datas.gachaTypeList
      const gachaLogs = this.$store.getters.datas.gachaLogs.data

      let count = 0
      for (const gachaType of gachaTypeList) {
        const gachaLogCount = gachaLogs[gachaType.key]
        count += gachaLogCount.length
      }

      return count
    },
    getRankCount (rank) {
      const miHoYoApi = new window.MiHoYoApi(this.$store.getters.datas.queryStringParameters)
      const gachaTypeList = this.$store.getters.datas.gachaTypeList
      const gachaLogs = this.$store.getters.datas.gachaLogs.data

      let count = 0
      for (const gachaType of gachaTypeList) {
        const listByRank = miHoYoApi.getListByRank(gachaLogs[gachaType.key], rank)
        count += listByRank.length
      }

      return count
    },
    getCharacterCount () {
      const miHoYoApi = new window.MiHoYoApi(this.$store.getters.datas.queryStringParameters)
      const gachaTypeList = this.$store.getters.datas.gachaTypeList
      const gachaLogs = this.$store.getters.datas.gachaLogs.data

      let count = 0
      for (const gachaType of gachaTypeList) {
        const listByCharacter = miHoYoApi.getListByCharacter(gachaLogs[gachaType.key])
        count += listByCharacter.length
      }

      return count
    },
    getWeaponCount () {
      const miHoYoApi = new window.MiHoYoApi(this.$store.getters.datas.queryStringParameters)
      const gachaTypeList = this.$store.getters.datas.gachaTypeList
      const gachaLogs = this.$store.getters.datas.gachaLogs.data

      let count = 0
      for (const gachaType of gachaTypeList) {
        const listByWeapon = miHoYoApi.getListByWeapon(gachaLogs[gachaType.key])
        count += listByWeapon.length
      }

      return count
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
  },
  watch: {
    '$i18n.locale': function () {
      this.title = this.$t('ui.text.title.home')
      window.titlebar.updateTitle(`${this.title} | ${this.$store.getters.configs.app.name}`) // 更新標題
    }
  }
}
</script>
