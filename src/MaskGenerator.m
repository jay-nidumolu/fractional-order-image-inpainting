function text_inpainting_mask(image_path, output_mask_path)
    img = im2double(imread(image_path));
    
    % Convert to grayscale if the image is in rgb
    if size(img, 3) == 3
        img = rgb2gray(img);
    end
    
    % Apply edge detection (Sobel operator)
    edges = edge(img, 'Sobel');
    
    % Dilation of edges to create a mask for text areas
    se = strel('disk', 2);
    dilated_edges = imdilate(edges, se);
    
    % Create an inpainting mask
    mask = zeros(size(img), 'like', img);  % Create a black mask
    
    % Insert the dilated edges into the mask (white areas will be inpainting regions)
    mask(dilated_edges > 0) = 1;  % Mark dilated edges as inpainting areas (white)
    
    % Save the mask as an image
    imwrite(mask, output_mask_path);
    
    % Display the results
    figure;
    subplot(1, 2, 1);
    imshow(img);
    title('Original Image');
    
    subplot(1, 2, 2);
    imshow(mask);
    title('Generated Inpainting Mask');
end

text_inpainting_mask('ReportData\Text\text_10.png', 'ReportData\EdgeMask\edgemask_10.png');