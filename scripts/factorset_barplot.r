library("gplots")
library("RColorBrewer")
file="/nfs/nobackup/ensembl/avilella/mmuc2008osn/work_dir/osn_mmu07/osn_mmu07.clusters.factorset.tsv"
i = read.table(file, sep="\t",header=TRUE)
summary(i)
rownames(i) = i$cluster_id
i = i[, !names(i) %in% "cluster_id"]
str(i)
m = as.matrix(head(i,n=1000))
h = hclust(dist(i))
heatmap(m)




rc <- rainbow(nrow(x), start=0, end=.3)
cc <- rainbow(ncol(x), start=0, end=.3)
hv <- heatmap(x, col = cm.colors(256), scale="column",
              RowSideColors = rc, ColSideColors = cc, margins=c(5,10),
              xlab = "specification variables", ylab= "Car Models",
              main = "heatmap(<Mtcars data>, ..., scale = \"column\")")
utils::str(hv) # the two re-ordering index vectors
