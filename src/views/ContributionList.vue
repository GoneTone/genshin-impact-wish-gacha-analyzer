<template>
  <navbar-layout></navbar-layout>

  <div id="content-wrapper" class="d-flex flex-column">
    <div id="content">
      <nav-layout></nav-layout>

      <div class="container-fluid mt-4" id="contributionList">
        <h1 class="h3 mb-2 text-gray-800">
          <i class="fas fa-fw fa-pencil-ruler"></i> {{ $t('ui.text.title.contribution_list.name') }}
        </h1>
        <p class="mb-4">{{ $t('ui.text.title.contribution_list.description') }}</p>

        <div class="card shadow mb-4">
          <div class="card-header py-3">
            <h6 class="m-0 font-weight-bold text-primary"><i class="fas fa-user-injured"></i> {{ $t('ui.text.project_leader') }}</h6>
          </div>
          <div class="card-body">
            <ul class="list-inline mb-0">
              <li class="list-inline-item" style="margin-right: 1.5rem;" v-for="(data, index) in contribution_list.project_leaders" :key="index">
                <span v-if="data.url">
                  <a :href="data.url">{{ data.name }}</a>
                </span>
                <span v-else>
                  {{ data.name }}
                </span>
              </li>
            </ul>
          </div>
        </div>

        <div class="card shadow mb-4">
          <div class="card-header py-3">
            <h6 class="m-0 font-weight-bold text-primary"><i class="fas fa-bug"></i> {{ $t('ui.text.testers') }}</h6>
          </div>
          <div class="card-body">
            <ul class="list-inline mb-0">
              <li class="list-inline-item" style="margin-right: 1.5rem;" v-for="(data, index) in contribution_list.testers" :key="index">
                <span v-if="data.url">
                  <a :href="data.url">{{ data.name }}</a>
                </span>
                <span v-else>
                  {{ data.name }}
                </span>
              </li>
            </ul>
          </div>
        </div>

        <div class="card shadow mb-4">
          <div class="card-header py-3">
            <h6 class="m-0 font-weight-bold text-primary"><i class="fab fa-github"></i> {{ $t('ui.text.github_contributor') }}</h6>
          </div>
          <div class="card-body">
            <a href="https://github.com/GoneTone/genshin-impact-wish-gacha-analyzer/graphs/contributors">https://github.com/GoneTone/genshin-impact-wish-gacha-analyzer/graphs/contributors</a>
          </div>
        </div>

        <div class="card shadow mb-4">
          <div class="card-header py-3">
            <h6 class="m-0 font-weight-bold text-primary"><i class="fas fa-language"></i> {{ $t('ui.text.translation_reviewer') }}</h6>
          </div>
          <div class="card-body">
            <ul class="list-inline mb-0">
              <li class="list-inline-item" style="margin-right: 1.5rem;" v-for="(data, index) in contribution_list.translation_reviewer" :key="index">
                <span v-if="data.url">
                  <a :href="data.url">{{ data.name }}</a>
                </span>
                <span v-else>
                  {{ data.name }}
                </span>
              </li>
            </ul>
          </div>
        </div>

        <div class="card shadow mb-4">
          <div class="card-header py-3">
            <h6 class="m-0 font-weight-bold text-primary"><i class="fas fa-language"></i> {{ $t('ui.text.translated_language') }}</h6>
          </div>
          <div class="card-body">
            <ul class="list-inline">
              <li class="list-inline-item" style="margin-right: 1.5rem;" v-for="locale in locales()" :key="`locale-${locale}`">
                {{ this.$store.getters.langNames[locale] }}
              </li>
            </ul>
            {{ $t('ui.text.help_translate_description') }}
            <br><a :href="this.$store.getters.configs.app.translationUrl">{{ this.$store.getters.configs.app.translationUrl }}</a>
          </div>
        </div>

        <div class="card shadow mb-4">
          <div class="card-header py-3">
            <h6 class="m-0 font-weight-bold text-primary"><i class="fab fa-github"></i> {{ $t('ui.text.project_license') }}</h6>
          </div>
          <div class="card-body">
            <a href="https://github.com/GoneTone/genshin-impact-wish-gacha-analyzer/blob/master/LICENSE">MIT License</a>
            <pre class="notranslate mt-3">
MIT License

Copyright (C) 2021 by GoneTone

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
            </pre>
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
import FooterLayout from '@/components/FooterLayout.vue'

export default {
  name: 'ContributionList',
  components: {
    NavbarLayout,
    NavLayout,
    FooterLayout
  },
  methods: {
    locales () {
      const locales = []
      for (const locale of this.$i18n.availableLocales) {
        if (this.$store.getters.langNames[locale] !== locale) {
          locales.push(locale)
        }
      }

      return locales
    }
  },
  data () {
    return {
      title: this.$t('ui.text.title.contribution_list.name'),
      contribution_list: {
        project_leaders: [
          {
            name: this.$store.getters.configs.developer.displayName,
            url: this.$store.getters.configs.developer.url
          }
        ],
        testers: [
          {
            name: '世界へいわ',
            url: 'https://home.gamer.com.tw/homeindex.php?owner=XMoiswnX'
          },
          {
            name: 'Zhi',
            url: 'https://www.hoyolab.com/genshin/accountCenter/gameRecord?id=8094152'
          }
        ],
        translation_reviewer: [
          {
            name: '世界へいわ',
            url: 'https://home.gamer.com.tw/homeindex.php?owner=XMoiswnX'
          },
          {
            name: 'pan93412'
          }
        ]
      }
    }
  },
  mounted () {
    window.titlebar.updateTitle(`${this.title} | ${this.$store.getters.configs.app.name}`) // 更新標題

    const _this = this
    ;(function ($) {
      $('#contributionList').on('click', 'a', (event) => {
        event.preventDefault()

        _this.$store.dispatch('playerAudioEffect', 'open_win') // 播放音效

        const nolink = event.target.getAttribute('data-nolink')
        if (!nolink) {
          const link = event.target.href
          window.shell.openExternal(link) // 使用外部瀏覽器
        }
      })
      // eslint-disable-next-line no-undef
    })(jQuery)
  },
  watch: {
    '$i18n.locale': function () {
      this.title = this.$t('ui.text.title.contribution_list.name')
      window.titlebar.updateTitle(`${this.title} | ${this.$store.getters.configs.app.name}`) // 更新標題
    }
  }
}
</script>
