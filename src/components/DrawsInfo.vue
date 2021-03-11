<template>
  <div class="card bg-info text-white shadow mb-4">
    <div class="card-body" v-if="isNoDisplayGuaranteed">
      目前累積 <kbd>{{ accumulateDraws.toString() }}</kbd> 抽，平均 <kbd>{{ averagDrawsCountInWin.toString() }}</kbd> 抽中5星。
    </div>
    <div class="card-body" v-else>
      目前累積 <kbd>{{ accumulateDraws.toString() }}</kbd> 抽，離上次已累積 <kbd>{{ accumulateNotWinDraws.toString() }}</kbd> 抽未出5星，平均 <kbd>{{ averagDrawsCountInWin.toString() }}</kbd> 抽中5星。
    </div>
  </div>
  <div class="progress mb-0" v-if="!isNoDisplayGuaranteed">
    <div class="progress-bar bg-bd6932" role="progressbar" :style="`width: ${progressPercentageComputed}%;`" :aria-valuenow="progressPercentageComputed" aria-valuemin="0" aria-valuemax="100">保底進度：{{ progressPercentageComputed.toString() }}%</div>
  </div>
  <p class="mb-4 text-bd6932" v-if="!isNoDisplayGuaranteed">距離保底還剩下 <kbd>{{ guaranteedCountComputed.toString() }}</kbd> 抽！</p>
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
