<template>
  <div class="mb-4">
    <h1 class="h3 text-gray-800">
      <i class="fas fa-fw fa-star"></i> {{ title }}
      <small class="text-muted">{{ dataTimeRange }}</small>
    </h1>
    <a @click="reload()" class="btn btn-sm btn-secondary btn-icon-split mr-2">
      <span class="icon text-white-50">
        <i class="fas fa-sync-alt"></i>
      </span>
      <span class="text">{{ $t("ui.text.update_data") }}</span>
    </a>
    <a @click="exportExcel()" class="btn btn-sm btn-primary btn-icon-split">
      <span class="icon text-white-50">
        <i class="fas fa-download"></i>
      </span>
      <span class="text">{{ $t("ui.text.export_excel") }}</span>
    </a>
    <p>{{ $t("ui.text.data_update_time", { time: updateTime }) }}</p>
  </div>
</template>

<script>
export default {
  name: 'HeaderLayout',
  props: {
    title: {
      type: String,
      required: true
    },
    dataTimeRange: {
      type: String,
      default: ''
    },
    updateTime: {
      type: String,
      required: true
    }
  },
  methods: {
    reload () {
      this.$store.dispatch('playerAudioEffect', 'switch_task') // 播放音效
      this.$store.dispatch('setDatas', true)
    },
    async exportExcel () {
      this.$store.dispatch('playerAudioEffect', 'switch_task') // 播放音效

      const exportGachaData = new window.ExportGachaData(this.$store.getters.datas.gachaTypeList, this.$store.getters.datas.gachaLogs.data)
      await exportGachaData.xlsx()
    }
  }
}
</script>
