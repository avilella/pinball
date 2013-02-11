## Scanning clusters file to get the list of cluster sizes
main=''
xlab="Number of reads per cluster"
ylab="Frequency"
xlim=c(20,30000)

args <- commandArgs(trailingOnly=TRUE)
if (length(args) != 1) {
cat("You must supply the clusters file as argument:\n Rscript cluster_size_scan_cmdline.r /path/to/file.clusters")
quit()
}

clustersfile=args[1]
df <- read.table(pipe(paste("awk '{print $1\"\t\"$2}'",clustersfile,"| uniq")))
print("All clusters")
print(summary(df$V2))
print("All clusters below 1M reads")
df = subset(df, V2<1000000)
print(summary(df$V2))
pois95 = paste("95% Poisson lambda mean =",qpois(0.95,mean(df$V2)))
print(pois95)
main=pois95
plot(table(df$V2),log="x",col="darkgrey",xlab=xlab,ylab=ylab,main=main,xlim=xlim)

11
