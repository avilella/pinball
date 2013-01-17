library("gplots")
ifile="/home/avilella/00x/osn_mmu07.clusters.factorset.tsv"
# ifile="/home/avilella/00x/oskm_hsap.clusters.factorset.c20.tsv"
i = read.table(ifile, sep="\t",header=TRUE, row.names = 1)
## i[2] = round(abs(rnorm(nrow(i),10)),0)
summary(i)
## rownames(i) = i$cluster_id
## i = i[, !names(i) %in% "cluster_id"]
str(i)
ncol(i)
## minfactor = round(mean(colMeans(i))/(ncol(i)*ncol(i)),0)
minfactor = 5
m0 = matrix(as.numeric(i>minfactor),nrow=nrow(i))
m = m0[rowSums(m0)>0,]
ms =m[order(as.vector(m %*% matrix(2^((ncol(m)-1):0),ncol=1)), decreasing=TRUE),]
head(ms)
tail(ms)
dwidth=8000
dheight=16000
## svg(width=dwidth,height=dheight,file=paste(ifile,".f",minfactor,".res",dwidth,"x",dheight,".heatmap.svg",sep=''),antialias="none")
## pdf(width=dwidth,height=dheight,file=paste(ifile,".f",minfactor,".res",dwidth,"x",dheight,".heatmap.pdf",sep=''),pointsize=20)
png(width=dwidth,height=dheight,file=paste(ifile,".f",minfactor,".res",dwidth,"x",dheight,".heatmap.png",sep=''))
### pdf(width=1200, height=2400,file=paste(ifile,".f",minfactor,".heatmap.pdf",sep=''))

heatmap.2(ms,
          distfun = dist,
          hclustfun = hclust,
          dendrogram="col",
          Rowv=FALSE,
          labRow=" ",
          labCol=colnames(i),
          trace="none",
          col=c("black","red"),
          density.info=c("none"),
          key=FALSE
          )

dev.off()

11

## rowci = rainbow(nrow(ms))
## colci = rainbow(ncol(ms))
## heatmap(ms,
##         Rowv=NA,
##         Colv=NA,
##         labRow=" ",
##         labCol=colnames(i),
##         keep.dendro = FALSE,
##         reorderfun=NA,
##         col=c("black","red"),
##         ColSideColors=colci,
##         )
