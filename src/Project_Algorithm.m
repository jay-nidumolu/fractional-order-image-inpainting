% Function to calculate g_m
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

%Initializing
input_image = im2double(rgb2gray(imread('ReportData\Noise\noise_1.png')));
original_image = im2double(im2gray(imread('ReportData\Original\original_1.png')));
mask = im2gray(imread('ReportData\EdgeMask\edgemask_1.png')); % Binary mask

lambda_m = 0;
delta_t = 0.01;
DC_m = 0;
alpha1 = 1;
alpha2 = 1;
sigma = 4;
kernel_size = 1;

[x, y] = meshgrid(linspace(-kernel_size/2, kernel_size/2, kernel_size));
h = (1/(2*pi*sigma^2)) * exp(-(x.^2 + y.^2) / (2*sigma^2));
h = h/sum(h(:));

padded_kernel = padarray(h, size(input_image) - size(h), 'post');

h_hat = fft2(padded_kernel);


u_m = input_image;
u0 = original_image;
u0_hat = fft2(u0);
u_initial = input_image;
u_hata_initial = fft2(u_initial);
edge_threshold = 0.1;

no_improve_count = 0;
max_no_improve_iter = 10;
tolerance = 1e-2;
psnr_prev = psnr(u_m, u0);
fprintf('Initial PSNR: %.6f\n', psnr_prev);
count = 0;

%Algorithm Loop
for m = 1:100
  
  u_hat_m = fft2(u_m);
      
  g_hat_m = fractional_inpainting(u_hat_m, mask, DC_m, alpha1, alpha2);

  reg_term = compute_regularization(lambda_m, h_hat, u_hat_m, u0_hat, mask);
      
  u_hat_m = u_hat_m - (g_hat_m * delta_t) - reg_term;
    
  u_m = ifft2(u_hat_m);

  

  [Gx, Gy] = gradient(u_m);
  G_mag = sqrt(Gx.^2 + Gy.^2);
  [u_xx, u_xy] = gradient(Gx);
  [~, u_yy] = gradient(Gy);
  u_eta_eta = (Gx.^2 .* u_xx + 2 * Gx .* Gy .* u_xy + Gy.^2 .* u_yy) ./ (G_mag.^2 + eps);
  u_xi_xi = (Gy.^2 .* u_xx - 2 * Gx .* Gy .* u_xy + Gx.^2 .* u_yy) ./ (G_mag.^2 + eps);
  DC_m = abs(abs(u_eta_eta) - abs(u_xi_xi));

  lambda_m = var(u_m(:)) / mean(u_m(:));

  psnr_new = psnr(real(u_m), u0);
  fprintf('Iteration PSNR: New = %.6f, Prev = %.6f, Diff = %.6f\n', psnr_new, psnr_prev, psnr_new - psnr_prev);
  imshow(u_m);
  if psnr_new > psnr_prev - tolerance
        psnr_prev = psnr_new;

  else
      if count == 2
           image_to_save = real(u_m); % If u_m contains complex values, take the real part

           % Normalize the image to the range [0, 255] for saving
           image_to_save = (image_to_save - min(image_to_save(:))) / (max(image_to_save(:)) - min(image_to_save(:))) * 255;

           % Convert to uint8
           image_to_save = uint8(image_to_save);

           % Save the image
           imwrite(image_to_save, 'ReportData\Noisy\model_1_20.png'); % Save to a PNG file
           break;
      else
          count = count + 1;
      end
  end

end