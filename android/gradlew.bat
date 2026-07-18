@echo off
setlocal
set GRADLE_VERSION=8.13
set CACHE_ROOT=%USERPROFILE%\.gradle\wrapper\dists\kouroshyar-gradle-%GRADLE_VERSION%
set GRADLE_HOME=%CACHE_ROOT%\gradle-%GRADLE_VERSION%
set ZIP_FILE=%CACHE_ROOT%\gradle-%GRADLE_VERSION%-bin.zip
if not exist "%GRADLE_HOME%\bin\gradle.bat" (
  if not exist "%CACHE_ROOT%" mkdir "%CACHE_ROOT%"
  powershell -NoProfile -ExecutionPolicy Bypass -Command "$u='https://services.gradle.org/distributions/gradle-%GRADLE_VERSION%-bin.zip'; Invoke-WebRequest -UseBasicParsing $u -OutFile '%ZIP_FILE%'; $expected=(Invoke-WebRequest -UseBasicParsing ($u+'.sha256')).Content.Trim(); $actual=(Get-FileHash -Algorithm SHA256 '%ZIP_FILE%').Hash.ToLower(); if($expected -ne $actual){throw 'Gradle distribution checksum mismatch'}; Expand-Archive -Force '%ZIP_FILE%' '%CACHE_ROOT%'"
  if errorlevel 1 exit /b 1
)
call "%GRADLE_HOME%\bin\gradle.bat" -p "%~dp0" %*
endlocal
