function  generateFeatureMaps(tif,res_microns,pad_microns)
%subj,specimen,slice,stain)


%default uses 100um+5um pad -- Maged's 20um used 50um pad -- 


if ~exist('res_microns')
    %resolution of output feature maps, in microns
    res_microns=100;
end

if ~exist('pad_microns')
    %padding of each chunk, in microns -- default is ~approx radius of neuron
    pad_microns=5;
end


%tif='F:\Histology\EPI_P040\tif\EPI_P040_Neo_06_NEUN.tif';
%tif='/links/Histology/EPI_P040/tif/EPI_P040_Hp_06_NEUN.tif'

[path,name,ext]=fileparts(tif);

split=strsplit(name,'_');

%get stain type at end of name:
s=name;

subj=name(1:8);
stain_type=split{end};
strct=split{end-2}; %Hp or Neo


lores_png=sprintf('%s/../%dum_png/%s.png',path,res_microns,name);

if ~exist(lores_png)
  system(sprintf('echo %s >> Missing_%dum_png.txt',lores_png,res_microns))
else
lores=imread(lores_png);
end


    
outdir=sprintf('%s/../%dum_FeatureMaps',path,res_microns);
mkdir(outdir);

%end

outmap=sprintf('%s/%s.mat',outdir,name);

%0.5um/pixel
hist_res=0.5;

scalefac=res_microns./hist_res;


imgSizes=mexAperioTiff(tif);

ds_size=ceil(imgSizes(1,:)./scalefac);
Nx=ds_size(1);
Ny=ds_size(2);


xout=0:0.5:255;
%maintain histogram
total_counts=zeros(size(xout));

skip_sweep=false;
%if feat map exists already, load it up and skip 1st sweep:
if (exist(outmap))
    skip_sweep=true;
    load(outmap);
end




%need two sweeps, first to compute histograms and determine optimal
%threshold, then to threshold and count # of positives

if (~skip_sweep)
    

%sweep 1:
for i=1:Nx
    i
    for j=1:Ny
        
    
        [img]=getHiresChunkAperio(tif,Nx,Ny,i,j,0,0); 
        
        stain_img=getStainChannel(img,stain_type);
        
        counts= hist(stain_img(:),xout);
        total_counts=total_counts+counts;
        
        
        
    end
    
end

threshold=getStainThreshold(xout,total_counts,stain_type);

end


features={'count','area','perimeter','orientation','weighted_orientation','eccentricity','clustering','field_fraction'};


featureVec=zeros(Nx,Ny,length(features));


%get features of big and small neurons too
sizeThreshold=500;
features_bysize={'count','area','perimeter','orientation','eccentricity'};
featureVec_sml=zeros(Nx,Ny,length(features_bysize));
featureVec_big=zeros(Nx,Ny,length(features_bysize));




%padwidth should be radius of pyramidal neuron (say 10um/2 = 5um)
padWidth=pad_microns./hist_res; %in pixels


%figure; 
%plot( fitresult{1}, xData, yData );

%roix=3:58;
%roiy=81:211;



%now, have threshold, do second sweep to get pos pix frac
for i=1:Nx
%    for i=roix
 %   i
    for j=1:Ny
%        for j=roiy
        
  %  j;
        [img]=getHiresChunkAperio(tif,Nx,Ny,i,j,0,padWidth); 
        
        
        stain_img=getStainChannel(img,stain_type);
        
        preWS=(threshold-stain_img)./255;         
        preWS(preWS<0)=0;
        
        
        %compute field fraction (on region with padding removed)
        nonpadimg=preWS(padWidth:(end-padWidth),padWidth:(end-padWidth));
        featureVec(i,j,8)=sum(nonpadimg(:)>0)/numel(nonpadimg);
        
        %remove border 
        preWS=preWS.*imclearborder(preWS>0);
        
        if(isempty(find(preWS>0)))
            
            %nothing passes the preWS threshold, skip this chunk..
            continue
        end
        
           
        if (strcmp(strct,'Neo'))
    
        [wL] = watershed2(preWS,5); 

        else if (strcmp(strct,'Hp'));
            
        [wL] = watershed2(preWS,6); 


        end 
        
        
        neuronCC=bwconncomp(wL);
        
            
        featureVec(i,j,1)=neuronCC.NumObjects;
       
        if (neuronCC.NumObjects > 0)
            
            props= regionprops(neuronCC,'Eccentricity','Area','Perimeter','Orientation','Centroid');  
            
            featureVec(i,j,2)=mean(cat(1,props.Area)).*hist_res^2;  %in units of um^2
            featureVec(i,j,3)=mean(cat(1,props.Perimeter));

          
            area=cat(1,props.Area);
            perim=cat(1,props.Perimeter);
            angle=cat(1,props.Orientation);
            eccen=cat(1,props.Eccentricity);
            centroid=cat(1,props.Centroid);

                        
            %get avg in cos space
            cos_mean=acos(mean(cos(angle/180*pi)))*180/pi;
            
            if (cos_mean>=45)
                angle(angle<0)=angle(angle<0)+180;
                featureVec(i,j,5)=mean((angle-90).*eccen)+90;
            else
                featureVec(i,j,5)=mean(angle.*eccen);
                
            end
            
            featureVec(i,j,4)=mean(angle); 
            featureVec(i,j,6)=mean(eccen);
            featureVec(i,j,7)=mean(pdist(centroid));
            
            
            % fill in featureVec_sml and featureVec_big
            % with features_bysize
            
            ind_sml=(cat(1,props.Area) < sizeThreshold);
            ind_big=(cat(1,props.Area) >= sizeThreshold);
            
            
            %count
            featureVec_sml(i,j,1)=sum(ind_sml);
            
            %area
            featureVec_sml(i,j,2)=mean(area(ind_sml));
            
            %perimeter
            featureVec_sml(i,j,3)=mean(perim(ind_sml));
            
            %angle:
            featureVec_sml(i,j,4)=mean(angle(ind_sml)); 
            
            %eccentricity
            featureVec_sml(i,j,5)=mean(eccen(ind_sml));

            
            %big neurons:
                        
            
            %count
            featureVec_big(i,j,1)=sum(ind_big);
            
            %area
            featureVec_big(i,j,2)=mean(area(ind_big));
            
            %perimeter
            featureVec_big(i,j,3)=mean(perim(ind_big));
            
            %angle:
            featureVec_big(i,j,4)=mean(angle(ind_big)); 
            
            %eccentricity
            featureVec_big(i,j,5)=mean(eccen(ind_big));
            
            
            
        end
        
       
    end
    
  %  disp(double(i)/double(Nx)*100);
    end


    %don't rotate yet... need to rotate orientations too!
    
%plot all features
 %figure;
 %for f=1:size(featureVec,3)
  %   subplot(1,size(featureVec,3),f); imagesc(featureVec(:,:,f));
  %   title(features{f});
  %  featureVec(:,:,f)=rotateImgTiffSpace(featureVec(:,:,f),tif);
 %end


save(outmap,'featureVec','features','total_counts','xout','threshold','featureVec_sml','featureVec_big','features_bysize');


%end %exist outmap

end
