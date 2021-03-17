<template>
  <div class="card bg-info text-white shadow mb-4">
    <div class="card-body" v-if="isNoDisplayGuaranteed" v-html="$t('ui.text.draws_info.msg1', { accumulate_draws: `<kbd>${accumulateDraws.toString()}</kbd>`, averag_draws_count_in_win: `<kbd>${averagDrawsCountInWin.toString()}</kbd>` })"></div>
    <div class="card-body" v-else v-html="$t('ui.text.draws_info.msg2', { accumulate_draws: `<kbd>${accumulateDraws.toString()}</kbd>`, accumulate_not_win_draws: `<kbd>${accumulateNotWinDraws.toString()}</kbd>`, averag_draws_count_in_win: `<kbd>${averagDrawsCountInWin.toString()}</kbd>` })"></div>
  </div>
  <div class="progress mb-0" v-if="!isNoDisplayGuaranteed">
    <div class="progress-bar bg-bd6932" role="progressbar" :style="`width: ${progressPercentageComputed}%;`" :aria-valuenow="progressPercentageComputed" aria-valuemin="0" aria-valuemax="100">{{ $t("ui.text.draws_info.guaranteed_progress", { progress: progressPercentageComputed.toString() }) }}</div>
  </div>
  <p class="mb-4 text-bd6932" v-if="!isNoDisplayGuaranteed" v-html="$t('ui.text.draws_info.guaranteed_count_msg', { count: `<kbd>${guaranteedCountComputed.toString()}</kbd>` })"></p>
</template>

<script>
export default {
  name: 'DrawsInfo',
  props: {
    gachaId: {
      type: Number
    },
    accumulateDraws: {
      type: Number,
      required: true
    },
    accumulateNotWinDraws: {
      type: Number
    },
    averagDrawsCountInWin: {
      type: Number,
      required: true
    },
    isNoDisplayGuaranteed: {
      type: Boolean
    }
  },
  data () {
    return {
      guaranteedCountComputed: this.getGuaranteedCountComputed(),
      progressPercentageComputed: this.getProgressPercentageComputed()
    }
  },
  methods: {
    getGuaranteedCountComputed () {
      let guaranteedCount = this.$store.getters.configs.game.guaranteedCount
      if (this.gachaId === 302) {
        guaranteedCount = this.$store.getters.configs.game.guaranteedCountForWeapon
      }

      return (guaranteedCount - this.accumulateNotWinDraws)
    },
    getProgressPercentageComputed () {
      let guaranteedCount = this.$store.getters.configs.game.guaranteedCount
      if (this.gachaId === 302) {
        guaranteedCount = this.$store.getters.configs.game.guaranteedCountForWeapon
      }

      if (isNaN((this.accumulateNotWinDraws / guaranteedCount))) {
        return 0
      }

      return Math.round(((this.accumulateNotWinDraws / guaranteedCount) * 100))
    }
  }
}
</script>
