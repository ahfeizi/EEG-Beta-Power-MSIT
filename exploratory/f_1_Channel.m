% --- انتخاب یک کانال ---
ch = 1;

[pxx_ch, freqs_ch] = pwelch(double(EEG.data(ch,:)'), ...
                             n_fft, n_overlap, n_fft, srate);

idx      = freqs_ch >= f_start & freqs_ch <= f_end;
f_sub_ch = freqs_ch(idx);
p_sub_ch = pxx_ch(idx);

% --- 1/f detrend ---
log_f_ch    = log10(f_sub_ch);
log_p_ch    = log10(p_sub_ch + 1e-30);
p_fit_ch    = polyfit(log_f_ch, log_p_ch, 1);
trend_ch    = polyval(p_fit_ch, log_f_ch);
residual_ch = log_p_ch - trend_ch;
res_smooth_ch = sgolayfilt(double(residual_ch), 3, 9);

% --- peak detection ---
min_dist = round(1 / (f_sub_ch(2) - f_sub_ch(1)));
[peak_vals, peak_locs] = findpeaks(res_smooth_ch, ...
    'MinPeakDistance',   min_dist, ...
    'MinPeakProminence', 0.02);
peak_freqs = f_sub_ch(peak_locs);

% --- رسم ---
figure('Name', sprintf('Channel %d — Beta Peak', ch), ...
       'Color', 'w', 'Position', [100 100 1400 450]);

% Panel 1: PSD خام
subplot(1, 3, 1);
plot(f_sub_ch, 10*log10(p_sub_ch * 1e12), 'b-', 'LineWidth', 2);
xlabel('Frequency (Hz)', 'FontSize', 11);
ylabel('PSD (dB re µV²/Hz)', 'FontSize', 11);
title(sprintf('Raw Beta PSD — Ch %d', ch), 'FontSize', 12, 'FontWeight', 'bold');
xlim([f_start f_end]);
grid on;

% Panel 2: log-log + 1/f trend
subplot(1, 3, 2);
plot(log_f_ch, log_p_ch, 'b-',  'LineWidth', 2, 'DisplayName', 'log PSD'); hold on;
plot(log_f_ch, trend_ch, 'r--', 'LineWidth', 2, 'DisplayName', '1/f trend');
xlabel('log_{10}(Frequency)', 'FontSize', 11);
ylabel('log_{10}(PSD)',       'FontSize', 11);
title('Log-Log + 1/f Trend', 'FontSize', 12, 'FontWeight', 'bold');
legend('Location', 'northeast', 'FontSize', 9);
grid on;

% Panel 3: residual + peaks
subplot(1, 3, 3);
plot(f_sub_ch, res_smooth_ch, 'Color', [0.55 0.27 0.07], 'LineWidth', 2);
hold on;
yline(0, '--', 'Color', [0.6 0.6 0.6], 'LineWidth', 1);

fill([f_sub_ch; flipud(f_sub_ch)], ...
     [max(res_smooth_ch, 0); zeros(length(f_sub_ch), 1)], ...
     [0.55 0.27 0.07], 'FaceAlpha', 0.12, 'EdgeColor', 'none');

if ~isempty(peak_locs)
    [~, best] = max(peak_vals);

    % همه peak ها
    plot(peak_freqs, res_smooth_ch(peak_locs), ...
         'o', 'Color', [0.2 0.2 0.6], ...
         'MarkerSize', 8, 'MarkerFaceColor', [0.2 0.2 0.6]);

    % برچسب همه peak ها
    for i = 1:length(peak_freqs)
        text(peak_freqs(i), ...
             res_smooth_ch(peak_locs(i)) + 0.008, ...
             sprintf('%.1f Hz', peak_freqs(i)), ...
             'HorizontalAlignment', 'center', ...
             'FontSize', 9, 'Color', [0.3 0.3 0.3]);
    end

    % dominant peak
    plot(peak_freqs(best), res_smooth_ch(peak_locs(best)), ...
         'p', 'Color', [0.8 0 0], ...
         'MarkerSize', 16, 'MarkerFaceColor', [0.8 0 0]);

    text(peak_freqs(best), ...
         res_smooth_ch(peak_locs(best)) + 0.018, ...
         sprintf('IBF = %.1f Hz', peak_freqs(best)), ...
         'HorizontalAlignment', 'center', ...
         'FontSize', 10, 'Color', [0.8 0 0], 'FontWeight', 'bold');
end

xlabel('Frequency (Hz)',       'FontSize', 11);
ylabel('Residual (log units)', 'FontSize', 11);
title(sprintf('Detrended Residual — Ch %d', ch), 'FontSize', 12, 'FontWeight', 'bold');
xlim([f_start f_end]);
grid on;

sgtitle(sprintf('Beta Peak Detection — Channel %d', ch), ...
        'FontSize', 14, 'FontWeight', 'bold');