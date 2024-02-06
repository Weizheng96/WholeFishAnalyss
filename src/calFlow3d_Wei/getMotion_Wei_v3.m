function phi_current=getMotion_Wei_v3(dat_mov,dat_ref,smoothPenalty)
%% v3: sequentially correct spatial smoothness

SZ=size(dat_mov);
layer_num = 3;              % pyramid layer num
movRange=[5 5 0.5];
pad_size = [20 20 2];  
step = 0.1;     % for calculate gradient

for layer = layer_num:-1:0

    data1 = imresize3(dat_mov, [round(SZ(1:2)/2^layer) SZ(3)]);
    data2 = imresize3(dat_ref, [round(SZ(1:2)/2^layer) SZ(3)]);

    [x,y,z] = size(data1);

    % pad image
    data1_pad = padarray(data1,pad_size,'replicate');
    gt2 = data2;
    
    % initilize the transform of each layer
    if layer == layer_num
        phi_current = gpuArray(zeros(x,y,z,3));
    else
        phi_current_temp=gather(phi_current);
        phi_current=zeros(x,y,z,3);
        phi_current(:,:,:,1) = imresize3(phi_current_temp(:,:,:,1), [x,y,z])*2;
        phi_current(:,:,:,2) = imresize3(phi_current_temp(:,:,:,2), [x,y,z])*2;
        phi_current(:,:,:,3) = imresize3(phi_current_temp(:,:,:,3), [x,y,z]);
        phi_current=gpuArray(phi_current);
    end
    
    [x_ind,y_ind,z_ind] = ind2sub(size(data1),1:x*y*z);
    
    
    for iter = 1:5
        phi_previous = phi_current;
        x_bias = reshape(phi_previous(:,:,:,1),[1 x*y*z]);
        y_bias = reshape(phi_previous(:,:,:,2),[1 x*y*z]);
        z_bias = reshape(phi_previous(:,:,:,3),[1 x*y*z]);
       
        % get tranformed data
        x_new = x_ind + x_bias;
        y_new = y_ind + y_bias;
        z_new = z_ind + z_bias;
        data1_tran = interp3(data1_pad,y_new+pad_size(2),x_new+pad_size(1),z_new+pad_size(3));
       
        % calculate xyz gradient
        x_new = x_new + step;
        data1_x_incre = interp3(data1_pad,y_new+pad_size(2),x_new+pad_size(1),z_new+pad_size(3));
       
        x_new = x_new - step;
        y_new = y_new + step;
        data1_y_incre = interp3(data1_pad,y_new+pad_size(2),x_new+pad_size(1),z_new+pad_size(3));
       
        y_new = y_new - step;
        z_new = z_new + step;
        data1_z_incre = interp3(data1_pad,y_new+pad_size(2),x_new+pad_size(1),z_new+pad_size(3));
       
    
        % get gradient and hessian matrix
        Ix = reshape((data1_x_incre - data1_tran)/step, [x y z]);
        Iy = reshape((data1_y_incre - data1_tran)/step, [x y z]);
        Iz = reshape((data1_z_incre - data1_tran)/step, [x y z]);
        It = reshape(data1_tran-gt2(:)', [x y z]);
    
        AverageFilter=ones(11,11,1);
        Ixx = imfilter(Ix.^2,AverageFilter,'replicate','same','corr');
        Ixy = imfilter(Ix.*Iy,AverageFilter,'replicate','same','corr');
        Ixz = imfilter(Ix.*Iz,AverageFilter,'replicate','same','corr');
        Iyy = imfilter(Iy.^2,AverageFilter,'replicate','same','corr');
        Iyz = imfilter(Iy.*Iz,AverageFilter,'replicate','same','corr');
        Izz = imfilter(Iz.^2,AverageFilter,'replicate','same','corr');
        Ixt = imfilter(Ix.*It,AverageFilter,'replicate','same','corr');
        Iyt = imfilter(Iy.*It,AverageFilter,'replicate','same','corr');
        Izt = imfilter(Iz.*It,AverageFilter,'replicate','same','corr');
    
        phi_gradient=getFlow3(Ixx,Ixy,Ixz,Iyy,Iyz,Izz,Ixt,Iyt,Izt);
        
        for dirNum=1:3
            phi_gradient(:,:,:,dirNum)=max(-movRange(dirNum),min(movRange(dirNum),phi_gradient(:,:,:,dirNum)));
        end
        phi_current = phi_current + phi_gradient;

        Diff=getDifferenceWithNei(phi_current);
        phi_current=phi_current-Diff*smoothPenalty;


    end

end

phi_current = gather(phi_current);

end