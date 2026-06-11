function g_hat_m = fractional_inpainting(U_hat, mask, DC, alpha1, alpha2)

    % Image size
    [M, N, P] = size(U_hat);
    
    % Generate frequency grid for DFT
    [Wx, Wy, Wz] = meshgrid(0:N-1, 0:M-1, 0:P-1);
    Wx = Wx / N; 
    Wy = Wy / M;
    Wz = Wz / P;
    
    % Compute fractional derivatives using DFT

    % for inpainting region
    Kx1 = (1 - exp(-1i * 2 * pi * Wx)).^alpha1 .* exp(1i * pi * Wx * alpha1);
    Ky1 = (1 - exp(-1i * 2 * pi * Wy)).^alpha1 .* exp(1i * pi * Wy * alpha1);
    Kz1 = (1 - exp(-1i * 2 * pi * Wz)).^alpha1 .* exp(1i * pi * Wz * alpha1);
    
    Dx_alpha1 = ifftn(Kx1 .* U_hat);
    Dy_alpha1 = ifftn(Ky1 .* U_hat);
    Dz_alpha1 = ifftn(Kz1 .* U_hat);

    kx1 = conj(Kx1);
    ky1 = conj(Ky1);
    kz1 = conj(Kz1);
    
    % for non-inpainting region
    Kx2 = (1 - exp(-1i * 2 * pi * Wx)).^alpha2 .* exp(1i * pi * Wx * alpha2);
    Ky2 = (1 - exp(-1i * 2 * pi * Wy)).^alpha2 .* exp(1i * pi * Wy * alpha2);
    Kz2 = (1 - exp(-1i * 2 * pi * Wz)).^alpha2 .* exp(1i * pi * Wz * alpha2);
    
    Dx_alpha2 = ifftn(Kx2 .* U_hat);
    Dy_alpha2 = ifftn(Ky2 .* U_hat);
    Dz_alpha2 = ifftn(Kz2 .* U_hat);

    kx2 = conj(Kx2);
    ky2 = conj(Ky2);
    kz2 = conj(Kz2);

    
    
    
    % Adaptive edge threshold
    MAD = median(abs(DC(:)) - median(abs(DC(:))));
    k = 1.4826 * MAD;
    
    % Conductance function
    f_DC = zeros(size(DC));
    f_DC(abs(DC) < k) = 1./(1 + (DC(abs(DC) < k) / k).^2);
    f_DC(abs(DC) >= k) = 0;
    
    inv_D_alpha2 = 1./(sqrt(Dx_alpha2.^2 + Dy_alpha2.^2 + Dz_alpha2.^2 + 1e-8));
    mask = double(mask);

    mask(mask > 0) = 1;
    
    % inpainting region
    lx_i =  f_DC .* Dx_alpha1; 
    lx_i(mask == 0) = 0;
    ly_i = f_DC .* Dy_alpha1;
    ly_i(mask ==0) = 0;
    lz_i = f_DC .* Dz_alpha1;
    lz_i(mask == 0) = 0;


    % Non - inpainting region
    lx_n = inv_D_alpha2 .* Dx_alpha2;
    lx_n(mask == 1) = 0;
    ly_n = inv_D_alpha2 .* Dy_alpha2;
    ly_n(mask == 1) = 0;
    lz_n = inv_D_alpha2 .* Dz_alpha2;
    lz_n(mask == 1) = 0;
    
    % gm 
    g_hat_m = zeros(size(U_hat));
    g_hat_temp_in = (kx1 .* fftn(lx_i)) + (ky1 .* fftn(ly_i)) + (kz1 .* fftn(lz_i));
    g_hat_m(mask==1) = g_hat_temp_in(mask==1);
    g_hat_temp_out = (kx2 .* fftn(lx_n)) + (ky2 .* fftn(ly_n)) + (kz2 .* fftn(lz_n));
    g_hat_m(mask == 0) = g_hat_temp_out(mask==0);
   
end



function [mssim_value, fom_value] = evaluate_metrics(original_image, restored_image, edge_threshold)
    % Ensure input images are real, normalized, and the same size
    original_image = real(original_image);
    restored_image = real(restored_image);
    if ~isequal(size(original_image), size(restored_image))
        error('Original and restored images must be of the same size.');
    end
    original_image = mat2gray(original_image); % Normalize to [0, 1]
    restored_image = mat2gray(restored_image); 
    
    
    % Compute MSSIM
    mssim_value = ssim(restored_image, original_image);
    
    % Compute Figure of Merit (FoM)
    edges_original = edge(original_image, 'canny', edge_threshold);
    edges_restored = edge(restored_image, 'canny', edge_threshold);
    
    % Parameters for FoM
    alpha = 1; % Default value for the falloff factor
    [rows, cols] = size(original_image);
    [y, x] = find(edges_restored); % Get edge points of the restored image
    
    % Calculate FoM
    fom_value = 0;
    num_edges = numel(find(edges_original)); % Total number of edge points in original image
    for i = 1:numel(x)
        % Find the minimum Euclidean distance to the closest edge in the original image
        dist = sqrt((y(i) - (1:rows)').^2 + (x(i) - (1:cols)).^2);
        [~, min_idx] = min(dist(:));
        fom_value = fom_value + 1 / (1 + alpha * dist(min_idx));
    end
    fom_value = fom_value / max(num_edges, 1); % Normalize by the number of edge points in the original
   
end

alpha_values = 0.2:0.2:2.5;

results = struct('alpha', [], 'psnr', [], 'mssim', [], 'fom', []);

    input_image = im2double(imread('ReportData\Text\text_10.png'));
    original_image = im2double(imread('ReportData\Original\original_10.png'));
    mask = imread('ReportData\EdgeMask\edgemask_10.png'); % Binary mask
    
    %Initializing
    lambda_m = 0;
    delta_t = 0.01;
    DC_m = 0;
    alpha1 = 1;
    alpha2 = 1;
    sigma = 4;
    kernel_size = 1;
    
    [x, y, z] = meshgrid(linspace(-kernel_size/2, kernel_size/2, kernel_size));
    h = (1/(2*pi*sigma^2)) * exp(-(x.^2 + y.^2 + z.^2) / (2*sigma^2));
    h = h/sum(h(:));

    kernel_size = size(h);
    input_size = size(h);
    while numel(kernel_size) < numel(input_size)
        kernel_size = [kernel_size, 1];
    end
    padded_kernel = padarray(h, input_size - kernel_size, 'post');
    
    h_hat = fftn(padded_kernel);
    
    
    u_m = input_image;
    u0 = original_image;
    u0_hat = fftn(u0);
    edge_threshold = 0.1;
    
    no_improve_count = 0;
    max_no_improve_iter = 10;
    tolerance = 1e-2;
    psnr_prev = psnr(u_m, u0);
    count = 0;
    
   for m = 0:50
      
      u_hat_m = fftn(u_m);
      
      
      g_hat_m = fractional_inpainting(u_hat_m, mask, DC_m, alpha1, alpha2);
      
      u_hat_m = u_hat_m - (g_hat_m * delta_t) - lambda_m * h_hat .* ((h_hat .* u_hat_m) - u0_hat);
    
      u_m = ifftn(u_hat_m);
    
      
    
      [Gx, Gy, Gz] = gradient(u_m);
      G_mag = sqrt(Gx.^2 + Gy.^2);
      [u_xx, u_xy, u_xz] = gradient(Gx); % Second derivatives involving Gx
      [~, u_yy, u_yz] = gradient(Gy);   % Second derivatives involving Gy
      [~, ~, u_zz] = gradient(Gz);
      u_eta_eta = (Gx.^2 .* u_xx + 2 * Gx .* Gy .* u_xy + 2 * Gx .* Gz .* u_xz + ...
             Gy.^2 .* u_yy + 2 * Gy .* Gz .* u_yz + ...
             Gz.^2 .* u_zz) ./ (G_mag.^2 + eps);
      u_xi_xi = (Gy.^2 .* u_xx - 2 * Gx .* Gy .* u_xy - 2 * Gx .* Gz .* u_xz + ...
           Gx.^2 .* u_yy - 2 * Gy .* Gz .* u_yz + ...
           Gz.^2 .* u_zz) ./ (G_mag.^2 + eps);
      DC_m = abs(abs(u_eta_eta) - abs(u_xi_xi));
    
      lambda_m = var(u_m(:)) / mean(u_m(:));
    
      psnr_new = psnr(real(u_m), u0);

      imshow(real(u_m));

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
   imwrite(real(u_m), 'ReportData\Model\model_10_3d.png');