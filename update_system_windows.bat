    @echo off
    chcp 65001 > nul
    setlocal enabledelayedexpansion
    cd /d "%~dp0"


    :: ANSI ЦВЕТА (Windows 10 1511+)
    for /f "tokens=*" %%a in ('powershell -NoProfile -Command "[char]27"') do set "ESC=%%a"
    set "C_RESET=!ESC![0m"
    set "C_OK=!ESC![1;32m"
    set "C_WARN=!ESC![1;33m"
    set "C_ERR=!ESC![1;31m"
    set "C_INFO=!ESC![36m"
    set "C_BOLD=!ESC![1m"
    set "C_DIM=!ESC![2m"
    set "C_SEC=!ESC![35m"

    :: СЧЁТЧИКИ
    set ERRORS_FOUND=0
    set ERRORS_COUNT=0
    set UPDATED_COUNT=0
    set SKIPPED_COUNT=0


    :: 1. создание папки для информации а если нет то создаем
    if exist "config.bat" (
        call config.bat
        if !errorlevel! neq 0 (
            call :cecho "!C_WARN!" "[ОШИБКА]" "Ошибка загрузки config.bat — стандартные настройки"
            set "LOG_DIR=%~dp0logs"
            set "LOG_FILE=%~dp0logs\update_system.log"
        )
    ) else (
        set "LOG_DIR=%~dp0logs"
        set "LOG_FILE=%~dp0logs\update_system.log"
    )

    if not exist "%LOG_DIR%" (
        mkdir "%LOG_DIR%"
        if !errorlevel! neq 0 (
            call :cecho "!C_ERR!" "[ОШИБКА]" "Не удалось создать директорию логов: %LOG_DIR%"
            pause & exit /b 1
        )
    )

    
    :: 2. права админа
    net session >nul 2>&1
    if %errorlevel% neq 0 (
        call :cecho "!C_INFO!" "[INFO]" "Запрос прав администратора..."
        powershell -Command "Start-Process '%~f0' -Verb RunAs"
        exit /b
    )

    :: 3. проверка winget
    where winget >nul 2>&1
    if %errorlevel% neq 0 (
        call :cecho "!C_ERR!" "[ОШИБКА]" "winget не найден! "
        call :log_message "[ОШИБКА] winget не найден"
        pause & exit /b 1
    )
    
    :: Аргументы и меню
    if /i "%~1"=="--safe"   goto mode_safe
    if /i "%~1"=="--full"   goto mode_full_with_exclude
    if /i "%~1"=="--check"  goto mode_preview
    if /i "%~1"=="--id" (
        if not "%~2"=="" ( set "name_id=%~2" & goto run_id_update )
        call :cecho "!C_ERR!" "[ОШИБКА]" "Укажите ID: --id Zoom.Zoom"
        pause & exit /b 1
    )
    if /i "%~1"=="--custom" (
        if not "%~2"=="" ( set "custom_list=%~2" & goto mode_custom )
        call :cecho "!C_ERR!" "[ОШИБКА]" "Укажите список: --custom Zoom.Zoom,Notion.Notion"
        pause & exit /b 1
    )

    call :cecho "!C_INFO!" "[INFO]" "Проверяем доступные обновления..."
    winget upgrade --include-unknown
    echo.
    echo !C_BOLD!  [Y]!C_RESET! Обновить !C_OK!ВСЕ!C_RESET! (с учётом ignore_list.txt)
    echo !C_BOLD!  [S]!C_RESET! Только !C_WARN!БЕЗОПАСНЫЕ!C_RESET! (из safe_list.txt)
    echo !C_BOLD!  [I]!C_RESET! Конкретную программу по !C_INFO!ID!C_RESET!
    echo !C_BOLD!  [C]!C_RESET! Только проверить !C_DIM!(Dry-run)!C_RESET!
    echo !C_BOLD!  [N]!C_RESET! !C_ERR!Выйти!C_RESET!
    echo.

    :: Выбор пользователя и дальнейшее действие 
    choice /C YSICN /M "Выбор:"
    if errorlevel 5 goto option_no
    if errorlevel 4 goto mode_preview
    if errorlevel 3 goto option_id
    if errorlevel 2 goto mode_safe
    if errorlevel 1 goto mode_full_with_exclude


    :: Все доступные обновления 
    :mode_preview
    echo.
    call :cecho "!C_SEC!" "[DRY-RUN]" "Доступные обновления:"
    call :log_message "Start (DRY-RUN)"
    winget upgrade --include-unknown
    set _ERR=!errorlevel!
    if !_ERR! neq 0 (
        call :log_message "[WARN] DRY-RUN код !_ERR!"
    ) else (
        call :log_message "Preview OK"
    )
    goto end


    :: Выбираем программки только из списка safe_list.txt
    :mode_safe
    echo.
    call :cecho "!C_SEC!" "[SAFE]" "Обновление ПО из белого списка..."
    if not exist "config\" (
        call :cecho "!C_ERR!" "[ОШИБКА]" "Директория config\ не найдена!"
        call :log_message "[ОШИБКА] config\ не найдена"
        goto end
    )
    if not exist "config\safe_list.txt" (
        call :cecho "!C_ERR!" "[ОШИБКА]" "config\safe_list.txt не найден!"
        call :log_message "[ОШИБКА] safe_list.txt не найден"
        goto end
    )
    call :log_message "Start (SAFE)"

    for /f "usebackq eol=# delims=" %%i in ("config\safe_list.txt") do (
        echo.
        call :cecho "!C_INFO!" "[...]" "Обновление: %%i"
        winget upgrade --id "%%i" --accept-source-agreements --accept-package-agreements
        set _ERR=!errorlevel!
        if !_ERR! EQU 0 (
            call :cecho "!C_OK!" "[OK]" "%%i — обновлён успешно"
            call :log_message "[OK] %%i"
            set /a UPDATED_COUNT+=1
        ) else if !_ERR! EQU -1978335215 (
            call :cecho "!C_WARN!" "[SKIP]" "%%i — уже последняя версия"
            set /a SKIPPED_COUNT+=1
        ) else (
            call :cecho "!C_ERR!" "[ОШИБКА]" "%%i — код !_ERR!"
            call :log_message "[ERR] %%i — !_ERR!"
            call :explain_winget_error "!_ERR!"
            set ERRORS_FOUND=1 & set /a ERRORS_COUNT+=1
        )
    )
    call :log_message "Finished (SAFE)"
    goto end


    :: Обновляем полностью всё программки
    :mode_full_with_exclude
    echo.
    call :cecho "!C_SEC!" "[FULL]" "Обновление всех программ с исключениями..."
    call :log_message "Start (FULL)"

    if exist "config\ignore_list.txt" (
        call :cecho "!C_WARN!" "[PIN]" "Блокировка пакетов из ignore_list.txt..."
        for /f "usebackq eol=# delims=" %%i in ("config\ignore_list.txt") do (
            winget pin add --id "%%i" --blocking >nul 2>&1
            set _ERR=!errorlevel!
            if !_ERR! neq 0 (
                call :cecho "!C_WARN!" "[WARN]" "Не удалось заблокировать: %%i (код !_ERR!)"
                call :log_message "[WARN] pin add %%i — !_ERR!"
            ) else (
                call :cecho "!C_INFO!" "[PIN]" "Заблокирован: %%i"
            )
        )
    )

    call :cecho "!C_INFO!" "[INFO]" "Запуск полного обновления..."
    winget upgrade --all --include-unknown --accept-source-agreements --accept-package-agreements
    set _FULL_ERR=!errorlevel!
    if !_FULL_ERR! neq 0 (
        call :cecho "!C_ERR!" "[ОШИБКА]" "FULL update — код !_FULL_ERR!"
        call :log_message "[ERR] FULL — !_FULL_ERR!"
        call :explain_winget_error "!_FULL_ERR!"
        set ERRORS_FOUND=1 & set /a ERRORS_COUNT+=1
    ) else (
        call :cecho "!C_OK!" "[OK]" "Полное обновление завершено успешно"
    )

    if exist "config\ignore_list.txt" (
        call :cecho "!C_INFO!" "[PIN]" "Снятие временных блокировок..."
        for /f "usebackq eol=# delims=" %%i in ("config\ignore_list.txt") do (
            winget pin remove --id "%%i" >nul 2>&1
            if !errorlevel! neq 0 (
                call :cecho "!C_WARN!" "[WARN]" "Не снята блокировка: %%i"
            )
        )
    )
    call :log_message "Finished (FULL)"
    goto end


    :: Умный конвеер , берет список програм и обновляем 
    :mode_custom
    echo.
    call :cecho "!C_SEC!" "[CUSTOM]" "Выбранные пакеты: %custom_list%"
    call :log_message "Start (CUSTOM) — %custom_list%"
    for %%p in (%custom_list%) do (
        call :cecho "!C_INFO!" "[...]" "Обновление %%p..."
        winget upgrade --id "%%p" --accept-source-agreements --accept-package-agreements
        set _ERR=!errorlevel!
        if !_ERR! EQU 0 (
            call :cecho "!C_OK!" "[OK]" "%%p — успешно"
            set /a UPDATED_COUNT+=1
        ) else (
            call :cecho "!C_ERR!" "[ОШИБКА]" "%%p — код !_ERR!"
            call :log_message "[ERR] %%p — !_ERR!"
            call :explain_winget_error "!_ERR!"
            set ERRORS_FOUND=1 & set /a ERRORS_COUNT+=1
        )
    )
    call :log_message "Finished (CUSTOM)"
    goto end


    :: Это режим если мы выбираем отдельную программу 
    :option_id
    set /p "name_id=Введите ID программы: "

    :run_id_update
    if "%name_id%"=="" (
        call :cecho "!C_ERR!" "[ОШИБКА]" "ID программы не может быть пустым!"
        goto end
    )
    call :cecho "!C_INFO!" "[INFO]" "Обновляем %name_id%..."
    call :log_message "Start (ID: %name_id%)"

    winget upgrade --id "%name_id%" --accept-source-agreements --accept-package-agreements
    set _ID_ERR=!errorlevel!

    if !_ID_ERR! EQU 0 (
        call :cecho "!C_OK!" "[OK]" "%name_id% — обновлён успешно"
        call :log_message "[OK] %name_id%"
        set /a UPDATED_COUNT+=1
    ) else if !_ID_ERR! EQU -1978335212 (
        call :cecho "!C_ERR!" "[ОШИБКА]" "Пакет не найден: %name_id%"
        call :cecho "!C_INFO!" "[TIP]" "Проверьте ID: winget search %name_id%"
        call :log_message "[ERR] Не найден: %name_id%"
        set ERRORS_FOUND=1 & set /a ERRORS_COUNT+=1
    ) else if !_ID_ERR! EQU -1978335215 (
        call :cecho "!C_WARN!" "[SKIP]" "%name_id% — уже установлена последняя версия"
        set /a SKIPPED_COUNT+=1
    ) else (
        call :cecho "!C_ERR!" "[ОШИБКА]" "%name_id% — код !_ID_ERR!"
        call :log_message "[ERR] %name_id% — !_ID_ERR!"
        call :explain_winget_error "!_ID_ERR!"
        set ERRORS_FOUND=1 & set /a ERRORS_COUNT+=1
    )
    call :log_message "Finished (ID: %name_id%)"
    goto end
    
    :: Отмена пользователя от обновлений 
    :option_no
    call :cecho "!C_WARN!" "[INFO]" "Обновление отменено пользователем."
    call :log_message "Отменено"
    goto end


    :: Конец скрипта итог скрипта 
    :end
    echo.
    echo   !C_BOLD!ИТОГИ РАБОТЫ СКРИПТА!C_RESET!
    echo   Обновлено:  !C_OK!%UPDATED_COUNT%!C_RESET!
    echo   Пропущено:  !C_WARN!%SKIPPED_COUNT%!C_RESET!
    if %ERRORS_COUNT% GTR 0 (
        echo   Ошибок:     !C_ERR!%ERRORS_COUNT% — смотрите лог!!C_RESET!
    ) else (
        echo   Ошибок:     !C_OK!нет!C_RESET!
    )
    echo   Лог: !C_DIM!%LOG_FILE%!C_RESET!
    call :log_message "=== DONE. OK:%UPDATED_COUNT% SKIP:%SKIPPED_COUNT% ERR:%ERRORS_COUNT% ==="
    pause
    exit /b !ERRORS_COUNT!


    :: Это у нас задаёт цвет
    :cecho
    set "_COLOR=%~1"
    set "_TAG=%~2"
    set "_MSG=%~3"
    echo !_COLOR!!_TAG!!C_RESET! !_MSG!
    call :log_message "!_TAG! !_MSG!"
    exit /b 0

    :: Запись событий с расшифровокой событий
    :log_message
    for /f "tokens=*" %%t in ('powershell -NoProfile -Command "Get-Date -Format [yyyy-MM-dd HH:mm:ss]"') do set _TS=%%t
    echo %_TS% %~1 >> "%LOG_FILE%"
    exit /b 0

    :: Расшифровка кодов ошибок winget (в случаи ошибок)
    :explain_winget_error
    set "_EC=%~1"
    if "%_EC%"=="-1978335212" call :cecho "!C_DIM!" "      →" "Пакет не найден в репозитории"
    if "%_EC%"=="-1978335215" call :cecho "!C_DIM!" "      →" "Уже установлена последняя версия"
    if "%_EC%"=="-1978335216" call :cecho "!C_DIM!" "      →" "Сбой инсталлятора пакета"
    if "%_EC%"=="-1978335188" call :cecho "!C_DIM!" "      →" "Инсталлятор заблокирован системой"
    if "%_EC%"=="-1978335189" call :cecho "!C_DIM!" "      →" "Требуется перезагрузка системы"
    if "%_EC%"=="-1978335203" call :cecho "!C_DIM!" "      →" "Установка отменена пользователем"
    if "%_EC%"=="-1978335230" call :cecho "!C_DIM!" "      →" "Нет сети или источник недоступен"
    exit /b 0