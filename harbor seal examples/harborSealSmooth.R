library(crawl)
library(ggplot2)
library(splines)
library(sp)
library(dplyr)
data(harborSeal)
head(harborSeal)
harborSeal$Argos_loc_class = factor(harborSeal$Argos_loc_class, levels=c("3","2","1","0","A","B"))

## Project data ##

toProj = harborSeal[!is.na(harborSeal$latitude),c("Time","latitude","longitude")]
coordinates(toProj) = ~longitude+latitude
proj4string(toProj) <- CRS("+proj=longlat")
toProj <- spTransform(toProj, CRS("+init=epsg:3338"))
toProj = as.data.frame(toProj)
colnames(toProj)[2:3] = c("x","y")
harborSeal = merge(toProj, harborSeal, by="Time", all=TRUE)
harborSeal = harborSeal[order(harborSeal$Time),]

initial = list(
  a=c(harborSeal$x[1],0,harborSeal$y[1],0),
  P=diag(c(10000^2,54000^2,10000^2,5400^2))
)

##Fit model as given in Johnson et al. (2008) Ecology 89:1208-1215
## Start values for theta come from the estimates in Johnson et al. (2008)

### Show all the parameters to provide start values and define a prior...
df=50
# 2m/s =2*60*60 m/h 
theta.start = c(rep(log(2000),3),log(2*60*60),rep(0,df),rep(0,df+1))

fixPar = c(log(250), log(500), log(1500), rep(NA,2*df+8-3), 0)

displayPar( mov.model=~bs(harborSeal$Time, df=df), err.model=list(x=~Argos_loc_class-1),data=harborSeal, 
                activity=~I(1-DryTime),fixPar=fixPar, theta=theta.start
                )

constr=list(lower=c(rep(log(1500),3),rep(-Inf,2*df+5-3)), upper=rep(Inf,2*df+5))
tune=1

prior = function(par){(sum(-abs(par[5:(df+4)])) + sum(-abs(par[(df+6):(2*df+5)])))/tune}

set.seed(321)
fit1 <- crwMLE(
  mov.model=~bs(harborSeal$Time, df=df), 
  err.model=list(x=~Argos_loc_class-1), activity=~I(1-DryTime),
  data=harborSeal, coord=c("x","y"), Time.name="Time", 
  initial.state=initial, fixPar=fixPar, 
  constr=constr,
  theta = theta.start,
  prior=prior,
  # initialSANN=list(maxit=2000, temp=100, tmax=5, trace=1, REPORT=1),
  control=list(maxit=2000, trace=1, REPORT=1)
)

print(fit1)

predTimes = floor(seq(min(harborSeal$Time), max(harborSeal$Time), by=6))[-1]

pred1 = crwPredict(fit1, predTime=predTimes, speedEst=FALSE, flat=TRUE, getUseAvail=FALSE) %>% 
  filter(locType=="p")

require(ggplot2)
p1=ggplot(aes(x=mu.x, y=mu.y), data=pred1) + geom_path(col="red") + geom_point(aes(x=x, y=y), col="blue") + coord_fixed()
p2=ggplot(aes(x=Time, y=mu.x), data=pred1) + geom_ribbon(aes(ymin=mu.x-2*se.mu.x, ymax=mu.x+2*se.mu.x), fill="green", alpha=0.5)  + 
  geom_path(, col="red") + geom_point(aes(x=Time, y=x), col="blue", size=1)
p3=ggplot(aes(x=Time, y=mu.y), data=pred1) + geom_ribbon(aes(ymin=mu.y-2*se.mu.y, ymax=mu.y+2*se.mu.y), fill="green", alpha=0.5)  + 
  geom_path(, col="red") + geom_point(aes(x=Time, y=y), col="blue", size=1)
print(p1)
print(p2)
print(p3)
# ggsave("map.pdf", p1)
# ggsave("xaxis.pdf", p2, width=10, height=2)
# ggsave("yaxis.pdf", p3, width=10, height=2)

displayPar( mov.model=~bs(harborSeal$Time, df=df), err.model=list(x=~Argos_loc_class-1),data=harborSeal, 
                activity=~I(1-DryTime),fixPar=fit1$par)

# time series of velocity correlation
vel.cor = exp(-exp(fit1$mov.mf%*%fit1$par[(df+8):(2*df+8)]))
#time series of velosity variance parameter
vel.sigma = exp(fit1$mov.mf%*%fit1$par[7:(df+7)])
# plot of correlation
plot(fit1$data$Time, vel.cor, type='l')
# plot of corrleation v. sigma
plot(vel.cor, vel.sigma, type='l')


### Experimental clustering for calculating behavior states
library(cluster)
mov_par = data.frame(ln_beta=fit1$mov.mf%*%fit1$par[(df+8):(2*df+8)], ln_sigma=fit1$mov.mf%*%fit1$par[7:(df+7)])
d = dist(mov_par, method = "euclidean") # distance matrix
clust = hclust(d, method="ward") 
states = cutree(clust, 3)
pred1$states = factor(states)

###
ggplot(data=pred1) + geom_point(aes(x=mu.x, y=mu.y, col=states), alpha=0.3)
