$ErrorActionPreference = 'Stop'
$androidToolConfig = Get-Content -LiteralPath 'D:\Workspace\DevelopmentTools\android-environment.json' -Raw | ConvertFrom-Json
$env:JAVA_HOME = $androidToolConfig.javaHome
$env:ANDROID_HOME = $androidToolConfig.androidHome
$env:ANDROID_USER_HOME = $androidToolConfig.androidUserHome
$env:ANDROID_AVD_HOME = $androidToolConfig.androidAvdHome
$env:GRADLE_USER_HOME = $androidToolConfig.gradleUserHome
$env:PATH = "$env:JAVA_HOME\bin;$env:ANDROID_HOME\platform-tools;$env:ANDROID_HOME\emulator;$env:PATH"
