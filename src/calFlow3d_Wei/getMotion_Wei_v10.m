function phi_current=getMotion_Wei_v10(dat_mov,dat_ref,smoothPenalty_raw)
%% v8: change z ratio with different downsample

SZ=size(dat_mov);
layer_num = 0;              % pyramid layer num
pad_size = [100 100 3];  
step = 1;     % for calculate gradient
iterNum=100;
zRatio_raw=27;
r=5;
movRange=[1 1 1/zRatio_raw]*r;

tempz=11;


for layer = layer_num:-1:0

    smoothPenalty=smoothPenalty_raw*2^layer;

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
    
    fprintf("\nDownsample:"+layer+"\n");
    temp1=zeros(x,y,iterNum);temp2=zeros(x,y,iterNum);
    temp3=zeros(x,y,iterNum);temp4=zeros(x,y,iterNum);
    temp5=zeros(x,y,iterNum);temp6=zeros(x,y,iterNum);
    errorHistory=zeros(iterNum,1);

%     oldPenaltyError=inf;
    for iter = 1:iterNum
        phi_previous = phi_current;
        x_bias = reshape(phi_previous(:,:,:,1),[1 x*y*z]);
        y_bias = reshape(phi_previous(:,:,:,2),[1 x*y*z]);
        z_bias = reshape(phi_previous(:,:,:,3),[1 x*y*z]);
       
        % get tranformed data
        x_new = x_ind + x_bias;
        y_new = y_ind + y_bias;
        z_new = z_ind + z_bias;
        data1_tran = interp3(data1_pad,y_new+pad_size(2),x_new+pad_size(1),z_new+pad_size(3));
        data1_tran = reshape(data1_tran, [x y z]);
       
        temp_diff1 = data1_tran(2,:,:) - data1_tran(1,:,:);
        temp_diff2 = (data1_tran(3:end,:,:) - data1_tran(1:end-2,:,:))/2;
        temp_diff3 = data1_tran(end,:,:) - data1_tran(end-1,:,:);
        Ix = cat(1,temp_diff1,temp_diff2,temp_diff3);
    
        temp_diff1 = data1_tran(:,2,:) - data1_tran(:,1,:);
        temp_diff2 = (data1_tran(:,3:end,:) - data1_tran(:,1:end-2,:))/2;
        temp_diff3 = data1_tran(:,end,:) - data1_tran(:,end-1,:);
        Iy = cat(2,temp_diff1,temp_diff2,temp_diff3);
    
        temp_diff1 = data1_tran(:,:,2) - data1_tran(:,:,1);
        temp_diff2 = (data1_tran(:,:,3:end) - data1_tran(:,:,1:end-2))/2;
        temp_diff3 = data1_tran(:,:,end) - data1_tran(:,:,end-1);
        Iz = cat(3,temp_diff1,temp_diff2,temp_diff3);
       
    
        % get gradient and hessian matrix
        It = data1_tran-gt2;
        It = imfilter(It,ones(3)/9,'replicate','same','corr');
    
        
        AverageFilter=ones(r*2+1);
        Ixx = imfilter(Ix.^2,AverageFilter,'replicate','same','corr');
        Ixy = imfilter(Ix.*Iy,AverageFilter,'replicate','same','corr');
        Ixz = imfilter(Ix.*Iz,AverageFilter,'replicate','same','corr');
        Iyy = imfilter(Iy.^2,AverageFilter,'replicate','same','corr');
        Iyz = imfilter(Iy.*Iz,AverageFilter,'replicate','same','corr');
        Izz = imfilter(Iz.^2,AverageFilter,'replicate','same','corr');
        Ixt = imfilter(Ix.*It,AverageFilter,'replicate','same','corr');
        Iyt = imfilter(Iy.*It,AverageFilter,'replicate','same','corr');
        Izt = imfilter(Iz.*It,AverageFilter,'replicate','same','corr');
 

        stepFactor=min((iter-1)/3,1);
        neiSum=smoothPenalty*stepFactor*getNeiSum2(phi_current,r);
        smoothPenaltySum=smoothPenalty*stepFactor*sum(AverageFilter,'all');
    
        zRatio=zRatio_raw/2^layer;
        phi_gradient=getFlow3_withPenalty3(Ixx,Ixy,Ixz,Iyy,Iyz,Izz,Ixt,Iyt,Izt,smoothPenaltySum,neiSum,zRatio);
        
        fprintf("gradient:\t");
        for dirNum=1:3
            phi_gradient(:,:,:,dirNum)=max(-movRange(dirNum),min(movRange(dirNum),phi_gradient(:,:,:,dirNum)));
            fprintf("\t"+gather(std(phi_gradient(:,:,:,dirNum),[],'all')))
        end
        fprintf("\n");
        phi_current = phi_current + phi_gradient;
        for dirNum=1:3
            phi_current(:,:,:,dirNum)=max(-pad_size(dirNum),min(pad_size(dirNum),phi_current(:,:,:,dirNum)));
        end



        %% calculate error (make it slow)
        data1_corrected=correctMotion_Wei(data1,phi_current);
        diffError=mean((data2-data1_corrected).^2,'all','omitnan');
        penaltyRaw=((r*2+1)^2-1)*phi_current-getNeiSum2(phi_current,r);
        penaltyRaw(:,:,:,3)=penaltyRaw(:,:,:,3)*zRatio;
        penaltyCorrected=sum(penaltyRaw.^2,4)*smoothPenalty;
        penaltyError=gather(mean(penaltyCorrected,'all'));

        fprintf("Downsample:"+layer+"\tIter:"+iter+"\tstep:\t"+stepFactor+"\tError:\t"+(diffError+penaltyError)+"\tDiff:\t"+diffError+"\n")

        temp1(:,:,iter)=data1_tran(:,:,tempz);
        temp2(:,:,iter)=phi_gradient(:,:,tempz,1);
        temp3(:,:,iter)=Ixt(:,:,tempz)./Ixx(:,:,tempz);
        temp4(:,:,iter)=It(:,:,tempz);
        temp5(:,:,iter)=data1_corrected(:,:,tempz);
        temp6(:,:,iter)=phi_current(:,:,tempz,1);
        errorHistory(iter)=diffError;

%         if oldPenaltyError>diffError || iter<5
%             oldPenaltyError=diffError;
%         else
%             phi_current=phi_previous;
%             break;
%         end

%         fprintf("Downsample:"+layer+"\tIter:"+iter+"\tstep:\t"+gather(std(phi_gradient(:,:,:,1:2),[],'all'))+"\n");
%         pause(1);


    end

end

phi_current = gather(phi_current);

end