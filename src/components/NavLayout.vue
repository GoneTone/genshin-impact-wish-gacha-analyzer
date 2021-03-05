<template>
  <nav class="navbar navbar-expand navbar-light bg-white topbar mb-4 static-top shadow">
    <button id="sidebarToggleTop" class="btn btn-link d-md-none rounded-circle mr-3">
      <i class="fa fa-bars"></i>
    </button>

    <ul class="navbar-nav ml-auto">
      <li class="nav-item dropdown no-arrow mx-1">
        <a class="nav-link" href="#" @click="openExternal(this.$store.getters.configs.team.facebookUrl);">
          <i class="fab fa-facebook-f fa-fw"></i>
        </a>
      </li>

      <li class="nav-item dropdown no-arrow mx-1">
        <a class="nav-link" href="#" @click="openExternal(this.$store.getters.configs.team.discordUrl);">
          <i class="fab fa-discord fa-fw"></i>
        </a>
      </li>

      <li class="nav-item dropdown no-arrow mx-1">
        <a class="nav-link" href="#" @click="openExternal(this.$store.getters.configs.app.githubUrl);">
          <i class="fab fa-github fa-fw"></i>
        </a>
      </li>

      <div class="topbar-divider d-none d-sm-block"></div>

      <li class="nav-item dropdown no-arrow">
        <a class="nav-link" href="#" @click="openExternal(this.$store.getters.configs.team.websiteUrl);">
          <span class="mr-2 text-gray-600 small">{{ this.$store.getters.configs.team.name }}</span>
        </a>
      </li>
    </ul>
  </nav>
</template>

<script>
export default {
  name: 'NavLayout',
  methods: {
    openExternal (link) {
      window.shell.openExternal(link)
    }
  }
}
</script>
