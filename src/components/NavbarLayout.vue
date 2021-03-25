<template>
  <ul class="navbar-nav bg-gradient-primary sidebar sidebar-dark accordion" id="accordionSidebar">
    <a class="sidebar-brand d-flex align-items-center justify-content-center" style="height: auto; padding: .7rem 1rem;">
      <div class="sidebar-brand-icon">
        <!--suppress CheckImageSize -->
        <img class="img-fluid" src="../../build/icons/256x256.png" width="64" alt="Icon">
      </div>
      <div class="sidebar-brand-text mx-3" style="text-transform: none;">{{ this.$store.getters.configs.app.name }} v{{ this.$store.getters.configs.app.version }}</div>
    </a>

    <hr class="sidebar-divider my-0">

    <li class="nav-item">
      <div class="form-group mb-0" style="display: block; padding: 0.5rem 1rem; color: #dddfeb">
        <div class="input-group">
          <div class="input-group-prepend">
            <div class="input-group-text"><i class="fas fa-language"></i></div>
          </div>
          <!--suppress HtmlFormInputWithoutLabel -->
          <select class="form-control" id="locales" v-model="$i18n.locale">
            <option v-for="locale in locales()" :key="`locale-${locale}`" :value="locale">{{ this.$store.getters.langNames[locale] }}</option>
          </select>
        </div>

        <div class="input-group mt-2">
          <div class="input-group-prepend">
            <div class="input-group-text"><i class="fas fa-address-card"></i></div>
          </div>
          <!--suppress HtmlFormInputWithoutLabel -->
          <select class="form-control" id="uidSelect" disabled>
            <option>{{ this.$store.getters.datas.playerUID }}</option>
          </select>
        </div>
      </div>
    </li>

    <hr class="sidebar-divider">

    <div class="sidebar-heading">
      {{ $t("ui.text.comprehensive") }}
    </div>

    <router-link to="/" v-slot="{ href, navigate, isActive }" custom>
      <li :class="['nav-item', isActive && 'active']">
        <a :class="['nav-link']" :href="href" @click="navigate">
          <i class="fas fa-fw fa-chart-pie"></i>
          <span>{{ $t("ui.text.title.home") }}</span>
        </a>
      </li>
    </router-link>

    <hr class="sidebar-divider">

    <div class="sidebar-heading">
      {{ $t("ui.text.various_gacha") }}
    </div>

    <router-link v-for="data of this.$store.getters.datas.gachaTypeList" :key="data.key" :to="{path: '/gacha/' + data.key}" v-slot="{ href, navigate, isActive }" custom>
      <li :class="['nav-item', isActive && 'active']">
        <a :class="['nav-link']" :href="href" @click="navigate">
          <i class="fas fa-star"></i>
          <span>{{ data.name }}</span>
        </a>
      </li>
    </router-link>

    <hr class="sidebar-divider">

    <div class="sidebar-heading">
      {{ $t("ui.text.other") }}
    </div>

    <router-link to="/history" v-slot="{ href, navigate, isActive }" custom>
      <li :class="['nav-item', isActive && 'active']">
        <a :class="['nav-link']" :href="href" @click="navigate">
          <i class="fas fa-fw fa-table"></i>
          <span>{{ $t("ui.text.title.history") }}</span>
        </a>
      </li>
    </router-link>

    <hr class="sidebar-divider">

    <div class="sidebar-heading">
      {{ $t("ui.text.about") }}
    </div>

    <li class="nav-item">
      <a class="nav-link" @click="openExternal(this.$store.getters.configs.team.websiteUrl);">
        <i class="fas fa-fw fa-globe"></i>
        <span>{{ this.$store.getters.configs.team.name }} - {{ $t("ui.text.official_website") }}</span>
      </a>
    </li>

    <li class="nav-item">
      <a class="nav-link collapsed" href="#" data-toggle="collapse" data-target="#collapseCommunity" aria-expanded="true" aria-controls="collapseCommunity">
        <i class="fas fa-fw fa-comments"></i>
        <span>{{ $t("ui.text.community") }}</span>
      </a>
      <div id="collapseCommunity" class="collapse" aria-labelledby="headingCommunity" data-parent="#accordionSidebar">
        <div class="bg-white py-2 collapse-inner rounded">
          <a class="collapse-item" @click="openExternal(this.$store.getters.configs.team.facebookUrl);"><i class="fab fa-facebook-f"></i> Facebook</a>
          <a class="collapse-item" @click="openExternal(this.$store.getters.configs.team.discordUrl);"><i class="fab fa-discord"></i> Discord</a>
        </div>
      </div>
    </li>

    <li class="nav-item">
      <a class="nav-link collapsed" href="#" data-toggle="collapse" data-target="#collapseDonate" aria-expanded="true" aria-controls="collapseDonate">
        <i class="fas fa-fw fa-donate"></i>
        <span>{{ $t("ui.text.donate_developer") }}</span>
      </a>
      <div id="collapseDonate" class="collapse" aria-labelledby="headingDonate" data-parent="#accordionSidebar">
        <div class="bg-white py-2 collapse-inner rounded">
          <h6 class="collapse-header">{{ $t("ui.text.donate_description") }}</h6>
          <a class="collapse-item" @click="openExternal('https://donate.reh.tw/');"><i class="fas fa-donate"></i> donate.reh.tw</a>
          <a class="collapse-item" @click="openExternal('https://paypal.me/GoneTone');"><i class="fab fa-paypal"></i> Paypal</a>
        </div>
      </div>
    </li>

    <hr class="sidebar-divider">

    <div class="sidebar-heading">
      {{ $t("ui.text.contribution") }}
    </div>

    <router-link to="/contribution-list" v-slot="{ href, navigate, isActive }" custom>
      <li :class="['nav-item', isActive && 'active']">
        <a :class="['nav-link']" :href="href" @click="navigate">
          <i class="fas fa-fw fa-pencil-ruler"></i>
          <span>{{ $t("ui.text.title.contribution_list.name") }}</span>
        </a>
      </li>
    </router-link>

    <li class="nav-item">
      <a class="nav-link" @click="openExternal(this.$store.getters.configs.app.translationUrl);">
        <i class="fas fa-fw fa-language"></i>
        <span>{{ $t("ui.text.help_translate") }}</span>
      </a>
    </li>

    <li class="nav-item">
      <a class="nav-link" @click="openExternal(`${this.$store.getters.configs.app.githubUrl}/issues`);">
        <i class="fab fa-fw fa-github"></i>
        <span>{{ $t("ui.text.issues_report") }}</span>
      </a>
    </li>

    <hr class="sidebar-divider d-none d-md-block">

    <div class="text-center d-none d-md-inline">
      <button class="rounded-circle border-0" id="sidebarToggle" @click="this.$store.dispatch('playerAudioEffect', 'switch_task')"></button>
    </div>
  </ul>
</template>

<script>
export default {
  name: 'NavbarLayout',
  methods: {
    locales () {
      const locales = []
      for (const locale of this.$i18n.availableLocales) {
        if (this.$store.getters.langNames[locale] !== locale) {
          locales.push(locale)
        }
      }

      return locales
    },
    openExternal (link) {
      this.$store.dispatch('playerAudioEffect', 'open_win') // 播放音效
      window.shell.openExternal(link)
    }
  },
  mounted () {
    this.$nextTick(function () {
      (function ($) {
        'use strict' // Start of use strict

        const sidebar = $('.sidebar')

        // Toggle the side navigation
        $('#sidebarToggle, #sidebarToggleTop').on('click', function () {
          $('body').toggleClass('sidebar-toggled')
          sidebar.toggleClass('toggled')
          if (sidebar.hasClass('toggled')) {
            $('.sidebar .collapse').collapse('hide')
          }
        })

        // Close any open menu accordions when window is resized below 768px
        $(window).resize(function () {
          if ($(window).width() < 768) {
            $('.sidebar .collapse').collapse('hide')
          }

          // Toggle the side navigation when window is resized below 480px
          if ($(window).width() < 480 && !sidebar.hasClass('toggled')) {
            $('body').addClass('sidebar-toggled')
            $('.sidebar').addClass('toggled')
            $('.sidebar .collapse').collapse('hide')
          }
        })

        // Prevent the content wrapper from scrolling when the fixed side navigation hovered over
        $('body.fixed-nav .sidebar').on('mousewheel DOMMouseScroll wheel', function (e) {
          if ($(window).width() > 768) {
            const e0 = e.originalEvent
            const delta = e0.wheelDelta || -e0.detail
            this.scrollTop += (delta < 0 ? 1 : -1) * 30
            e.preventDefault()
          }
        })

        // Scroll to top button appear
        $('.container-after-titlebar').on('scroll', function () {
          const scrollDistance = $(this).scrollTop()
          if (scrollDistance > 100) {
            $('.scroll-to-top').fadeIn()
          } else {
            $('.scroll-to-top').fadeOut()
          }
        })

        // Smooth scrolling using jQuery easing
        $('.scroll-to-top').on('click', function (e) {
          const $anchor = $(this)
          $('.container-after-titlebar').stop().animate({
            scrollTop: ($($anchor.attr('href')).offset().top)
          }, 1000, 'easeInOutExpo')
          e.preventDefault()
        })
        // eslint-disable-next-line no-undef
      })(jQuery) // End of use strict
    })
  }
}
</script>
