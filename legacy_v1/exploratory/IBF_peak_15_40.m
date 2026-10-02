% ============================================
% Beta Peak Analysis with 1/f Detrending
% رویکرد ۱: detrend در فضای log-log، peak detection روی residual
% فرض: EEG از قبل لود شده در EEGLAB
% ============================================

% --- پارامترها ---
f_start   = 15;
f_end     = 40;
epoch_len = 4;       % طول پنجره Welch (ثانیه)
overlap   = 0.5;     % 50% overlap

srate     = EEG.srate;
n_fft     = epoch_len * srate;
n_overlap = round(n_fft * overlap);

% --- انتخاب داده: میانگین روی همه کانال‌ها ---
% برای کانال خاص: 
data_mean = EEG.data(1, :);
% data_mean = mean(EEG.data, 1);

% --- محاسبه PSD با pwelch ---
[pxx, freqs] = pwelch(data_mean(:), n_fft, n_overlap, n_fft, srate);

% --- برش ۱۵ تا ۴۰ هرتز ---
idx   = freqs >= f_start & freqs <= f_end;
f_sub = freqs(idx);
p_sub = pxx(idx);

% --- رویکرد ۱: حذف 1/f در فضای log-log ---
log_f = log10(f_sub);
log_p = log10(p_sub + 1e-30);

% برازش خط به log-log (حذف روند 1/f)
p_fit    = polyfit(log_f, log_p, 1);
trend    = polyval(p_fit, log_f);
residual = log_p - trend;

% smooth کردن residual با Savitzky-Golay
residual_smooth = sgolayfilt(double(residual), 3, 9);

% --- peak detection روی residual ---
% MinPeakDistance: دو peak نمیتونن کمتر از ۱ Hz فاصله داشته باشن
% MinPeakProminence: روی residual (log units) — نه PSD خام
min_dist = round(1 / (f_sub(2) - f_sub(1)));

[peak_vals, peak_locs] = findpeaks(residual_smooth, ...
    'MinPeakDistance',   min_dist, ...
    'MinPeakProminence', 0.02);

peak_freqs = f_sub(peak_locs);

% --- نمایش نتایج ---
fprintf('\n===== Beta Local Maxima (1/f Detrended) =====\n');
if isempty(peak_freqs)
    fprintf('  هیچ peak‌ای پیدا نشد.\n');
else
    for i = 1:length(peak_freqs)
        fprintf('  Peak %d:  %.1f Hz  (prominence = %.4f log units)\n', ...
                i, peak_freqs(i), peak_vals(i));
    end
    [~, best] = max(peak_vals);
    fprintf('\n  IBF (dominant peak): %.1f Hz\n', peak_freqs(best));
end
fprintf('=============================================\n');

% --- رسم نمودار: ۳ panel ---
% figure('Name', 'Beta Peak Detection — 1/f Detrended', ...
%        'Color', 'w', 'Position', [100 100 1400 450]);
% 
% % --- Panel 1: PSD خام باند بتا ---
% subplot(1, 3, 1);
% plot(f_sub, 10*log10(p_sub * 1e12), 'b-', 'LineWidth', 2);
% xlabel('Frequency (Hz)', 'FontSize', 11);
% ylabel('PSD (dB re µV²/Hz)',  'FontSize', 11);
% title('Raw Beta PSD', 'FontSize', 12, 'FontWeight', 'bold');
% xlim([f_start f_end]);
% grid on;
% 
% % --- Panel 2: log-log + خط روند 1/f ---
% subplot(1, 3, 2);
% plot(log_f, log_p,  'b-',  'LineWidth', 2, 'DisplayName', 'log PSD'); hold on;
% plot(log_f, trend,  'r--', 'LineWidth', 2, 'DisplayName', '1/f trend');
% xlabel('log_{10}(Frequency)', 'FontSize', 11);
% ylabel('log_{10}(PSD)',       'FontSize', 11);
% title('Log-Log + 1/f Trend', 'FontSize', 12, 'FontWeight', 'bold');
% legend('Location', 'northeast', 'FontSize', 9);
% grid on;

% --- Panel 3: residual + peak های تشخیص داده شده ---
% subplot(1, 3, 3);
figure;
plot(f_sub, residual_smooth,  'LineWidth', 2);
hold on;
yline(0, '--', 'Color', [0.5 0.5 0.5], 'LineWidth', 1);

% % سایه زیر residual مثبت
% fill([f_sub; flipud(f_sub)], ...
%      [max(residual_smooth, 0); zeros(length(f_sub), 1)], ...
%      [0.55 0.27 0.07], 'FaceAlpha', 0.12, 'EdgeColor', 'none');

plot(peak_freqs, residual_smooth(peak_locs), ...
         'o', 'Color', [0 0 0.5], ...
         'MarkerSize', 8, 'MarkerFaceColor', [0 0 0.5]);
for i = 1:length(peak_freqs)
    text(peak_freqs(i), ...
         residual_smooth(peak_locs(i)) + 0.03, ...
         sprintf('%.1f Hz', peak_freqs(i)), ...
         'HorizontalAlignment', 'center');
end

xlabel('Frequency (Hz)',        'FontSize', 11);
ylabel('Residual (log units)',  'FontSize', 11);
% title('Detrended Residual — Peak Detection', 'FontSize', 12, 'FontWeight', 'bold');
xlim([f_start f_end]);
ylim([min(residual_smooth)-0.1 max(residual_smooth)+0.1])
grid on;

% sgtitle('Beta Peak Detection with 1/f Detrending', ...
%         'FontSize', 14, 'FontWeight', 'bold');