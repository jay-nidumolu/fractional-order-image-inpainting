function g_hat_m = fractional_inpainting(U_hat, mask, DC, alpha1, alpha2)

    % Image size
    [M, N] = size(U_hat);
    
    % Generate frequency grid for DFT
    [Wx, Wy] = meshgrid(0:N-1, 0:M-1);
    Wx = Wx / N; 
    Wy = Wy / M;
    
    % Compute fractional derivatives using DFT

    % for inpainting region
    Kx1 = diag((1 - exp(-1i * 2 * pi * Wx)).^alpha1 .* exp(1i * pi * Wx * alpha1));
    Ky1 = diag((1 - exp(-1i * 2 * pi * Wy)).^alpha1 .* exp(1i * pi * Wy * alpha1));
    
    Dx_alpha1 = ifft2(Kx1 .* U_hat);
    Dy_alpha1 = ifft2(Ky1 .* U_hat);

    kx1 = conj(Kx1);
    ky1 = conj(Ky1);
    
    % for non-inpainting region
    Kx2 = diag((1 - exp(-1i * 2 * pi * Wx)).^alpha2 .* exp(1i * pi * Wx * alpha2));
    Ky2 = diag((1 - exp(-1i * 2 * pi * Wy)).^alpha2 .* exp(1i * pi * Wy * alpha2));
    
    Dx_alpha2 = ifft2(Kx2 .* U_hat);
    Dy_alpha2 = ifft2(Ky2 .* U_hat);

    kx2 = conj(Kx2);
    ky2 = conj(Ky2);
    
    
    
    % Adaptive edge threshold
    MAD = median(abs(DC(:)) - median(abs(DC(:))));
    k = 1.4826 * MAD;
    
    % Conductance function
    f_DC = zeros(size(DC));
    f_DC(abs(DC) < k) = 1./(1 + (DC(abs(DC) < k) / k).^2);
    f_DC(abs(DC) >= k) = 0;
    
    inv_D_alpha2 = 1./(sqrt(Dx_alpha2.^2 + Dy_alpha2.^2 + 1e-8));
    mask = double(mask);

    mask(mask > 0) = 1;
    
    % inpainting region
    lx_i =  f_DC .* Dx_alpha1; 
    lx_i(mask == 0) = 0;
    ly_i = f_DC .* Dy_alpha1;
    ly_i(mask ==0) = 0;


    % Non - inpainting region
    lx_n = inv_D_alpha2 .* Dx_alpha2;
    lx_n(mask == 1) = 0;
    ly_n = inv_D_alpha2 .* Dy_alpha2;
    ly_n(mask == 1) = 0;
    
    % gm 
    g_hat_m = zeros(size(U_hat));
    g_hat_temp_in = (kx1 .* fft2(lx_i)) + (ky1 .* fft2(ly_i));
    g_hat_m(mask==1) = g_hat_temp_in(mask==1);
    g_hat_temp_out = (kx2 .* fft2(lx_n)) + (ky2 .* fft2(ly_n));
    g_hat_m(mask == 0) = g_hat_temp_out(mask==0);
   
end

%Function for calculating the regularirization term
function result = compute_regularization(lambda_m, h_hat, u_hat_m, u0_hat, mask)
    
    result = lambda_m * h_hat .* ((h_hat .* u_hat_m) - u0_hat);
    result(mask == 1) = 0;
end

% Read the RGB image and convert to double
input_image = im2double(imread('ReportData\Text\text_10.png'));
original_image = im2double(imread('ReportData\Original\original_10.png'));
mask = im2double(im2gray(imread('ReportData\EdgeMask\edgemask_10.png'))); % Convert mask to grayscale

% Separate RGB channels
input_R = input_image(:, :, 1);
input_G = input_image(:, :, 2);
input_B = input_image(:, :, 3);

original_R = original_image(:, :, 1);
original_G = original_image(:, :, 2);
original_B = original_image(:, :, 3);


% Parameters
lambda_m = 0;
delta_t = 0.01;
DC_m = 0;
alpha1 = 1;
alpha2 = 1;
sigma = 4;
kernel_size = 1;

[x, y] = meshgrid(linspace(-kernel_size/2, kernel_size/2, kernel_size));
h = (1/(2*pi*sigma^2)) * exp(-(x.^2 + y.^2) / (2*sigma^2));
h = h / sum(h(:));

% Pad the kernel to match the image size
padded_kernel = padarray(h, size(input_R) - size(h), 'post');
h_hat = fft2(padded_kernel);

% Function to apply inpainting on a single channel
function inpainted_channel = inpaint_channel(input_channel, original_channel, mask, h_hat, delta_t, lambda_m, alpha1, alpha2, DC_m)
    % Initialize variables
    u_m = input_channel;
    u0 = original_channel;
    u0_hat = fft2(u0);

    psnr_prev = psnr(u_m, u0);
    fprintf('Initial PSNR: %.6f\n', psnr_prev);
    count = 0;
    tolerance = 1e-2;

    for m = 1:100
        % Compute Fourier transform of the current estimate
        u_hat_m = fft2(u_m);

        % Fractional inpainting step (you should replace this with your actual fractional_inpainting function)
        g_hat_m = fractional_inpainting(u_hat_m, mask, DC_m, alpha1, alpha2);

        reg_term = compute_regularization(lambda_m, h_hat, u_hat_m, u0_hat, mask);

        % Update the estimate
        u_hat_m = u_hat_m - (g_hat_m * delta_t) - reg_term;
        u_m = ifft2(u_hat_m);

        % Compute Difference Curvature (DC)
        [Gx, Gy] = gradient(u_m);
        G_mag = sqrt(Gx.^2 + Gy.^2);
        [u_xx, u_xy] = gradient(Gx);
        [~, u_yy] = gradient(Gy);
        u_eta_eta = (Gx.^2 .* u_xx + 2 * Gx .* Gy .* u_xy + Gy.^2 .* u_yy) ./ (G_mag.^2 + eps);
        u_xi_xi = (Gy.^2 .* u_xx - 2 * Gx .* Gy .* u_xy + Gx.^2 .* u_yy) ./ (G_mag.^2 + eps);
        DC_m = abs(abs(u_eta_eta) - abs(u_xi_xi));

        % Update lambda_m dynamically
        lambda_m = var(u_m(:)) / mean(u_m(:));

        % Compute PSNR and check for convergence
        psnr_new = psnr(real(u_m), u0);
        %fprintf('Iteration PSNR: New = %.6f, Prev = %.6f, Diff = %.6f\n', psnr_new, psnr_prev, psnr_new - psnr_prev);
        if psnr_new > psnr_prev - tolerance
            psnr_prev = psnr_new;
        else
            if count == 2
                break;
            else
                count = count + 1;
            end
        end
    end

    % Return the inpainted channel
    inpainted_channel = real(u_m);
end

% Apply the inpainting function to each channel
output_R = inpaint_channel(input_R, original_R, mask, h_hat, delta_t, lambda_m, alpha1, alpha2, DC_m);
output_G = inpaint_channel(input_G, original_G, mask, h_hat, delta_t, lambda_m, alpha1, alpha2, DC_m);
output_B = inpaint_channel(input_B, original_B, mask, h_hat, delta_t, lambda_m, alpha1, alpha2, DC_m);

% Create color images for each channel
color_R = cat(3, output_R, zeros(size(output_R)), zeros(size(output_R))); % Red channel
color_G = cat(3, zeros(size(output_G)), output_G, zeros(size(output_G))); % Green channel
color_B = cat(3, zeros(size(output_B)), zeros(size(output_B)), output_B); % Blue channel

% Combine the inpainted channels back into an RGB image
output_image = cat(3, output_R, output_G, output_B);

% Normalize the output image to [0, 255]
output_image = (output_image - min(output_image(:))) / (max(output_image(:)) - min(output_image(:))) * 255;
output_image = uint8(output_image);

figure;
subplot(1,4,1), imshow(color_R), title('output_R');
subplot(1,4,2), imshow(color_G), title('output_G');
subplot(1,4,3), imshow(color_B), title('output_B');
subplot(1,4,4), imshow(output_image), title('output_image');
saveas(gcf, 'ReportData\Model\RGB_Channels.png'); % Save as a PNG file

% Save the inpainted image
imwrite(output_image, 'ReportData\Model\model_10_splitchannel.png');
%saveas(gcf, 'RGB_Channels.png'); % Save as a PNG file