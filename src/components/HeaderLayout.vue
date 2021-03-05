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
      <span class="text">更新資料</span>
    </a>
    <a @click="exportExcel()" class="btn btn-sm btn-primary btn-icon-split">
      <span class="icon text-white-50">
        <i class="fas fa-download"></i>
      </span>
      <span class="text">導出 Excel</span>
    </a>
    <p>資料更新時間：{{ updateTime }}</p>
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
      this.$store.dispatch('setDatas', true)
    },
    async exportExcel () {
      const exportGachaData = new window.ExportGachaData(this.$store.getters.datas.gachaTypeList, this.$store.getters.datas.gachaLogs.data)
      await exportGachaData.xlsx()
    }
  }
}
</script>
