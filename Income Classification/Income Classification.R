#Given various features, the aim is to build a predictive model to determine the income
#level for people in US. The income levels are binned at below 50K and above 50K.

#Train and Test datasets from UCI Machine Learning Repository
#The data is large and high dimensional. Used data.table for fast processing.

#Let’s think of some hypothesis which can influence the outcome.

#Here is a set of hypothesis:
#Hò : There is no significant impact of the variables (below) on the dependent variable.
#Ha : There exists a significant impact of the variables (below) on the dependent variable.

# Age
# Marital Status
# Income
# Family Members
# No. of Dependents
# Tax Paid
# Investment (Mutual Fund, Stock)
# Return from Investments
# Education
# Spouse Education
# Nationality
# Occupation
# Region in US
# Race
# Occupation category

#loading libraries
library(data.table)
library(ggplot2)
library(plotly)
library(caret)
library(ROSE)
library(xgboost)
library(mlr)
#loading data
train <- fread('train.csv',na.strings = c(""," ","?","NA",NA))
test <- fread('test.csv',na.strings = c(""," ","?","NA",NA))

#DATA EXPLORATION

#look at data
dim(train)
str (train)
View(train)

dim(test)
str (test)
View(test)

#Train data has 199523 rows & 41 columns. Test data has 99762 rows and 41 columns. 

#take a look at target variable
unique(train$income_level)
unique(train$income_level)

#encode target variables
train[, income_level := ifelse(income_level == "-50000",0,1)]
test[, income_level := ifelse(income_level == "-50000",0,1)]

#look at imbalanced classes
round(prop.table(table(train$income_level))*100)
 
#set column classes
factcols <- c(2:5,7,8:16,20:29,31:38,40,41)
numcols <- setdiff(1:40,factcols)

#With data table chaining, we can convert classes in one line
train[,(factcols) := lapply(.SD, factor), .SDcols = factcols][,(numcols) := lapply(.SD, as.numeric), .SDcols = numcols]
test[,(factcols) := lapply(.SD, factor), .SDcols = factcols][,(numcols) := lapply(.SD, as.numeric), .SDcols = numcols]
                   
#separate categorical variables and numerical variables
num_train <- train[, numcols, with = FALSE]
cat_train <- train[, factcols, with = FALSE]
num_test <- test[, numcols, with = FALSE]
cat_test <- test[, factcols, with = FALSE]

#save memory
rm(train,test) 

#write a plot function
plot_dist <- function(a){
  ggplot(data = num_train, aes(x= a, y=..density..)) + geom_histogram(fill="green",color="white",
                                        alpha = 0.5,bins =100) + geom_density()
  ggplotly()
}

#checking distribution
plot_dist(num_train$age)
plot_dist(num_train$wage_per_hour)
plot_dist(num_train$capital_gains)
plot_dist(num_train$capital_losses)
plot_dist(num_train$dividend_from_Stocks)
plot_dist(num_train$num_person_Worked_employer)
plot_dist(num_train$weeks_worked_in_year)

#nothing interesting above except for age variable. Now let us see how
#variables affect our target
num_train[, income_level := cat_train$income_level]

ggplot(data = num_train, aes(x = age, y = wage_per_hour)) +
              geom_point(aes(colour = income_level)) +
              scale_y_continuous("wage per hour", breaks = seq(0,10000,1000))

ggplot(data = num_train, aes(x = weeks_worked_in_year, y = wage_per_hour)) +
  geom_point(aes(colour = income_level)) +
  scale_y_continuous("wage per hour", breaks = seq(0,10000,1000))

#dodged bar chart function
plot_dodgedbar <- function(a){
  ggplot(cat_train, aes(x = a, fill = income_level)) +
    geom_bar(position = 'dodge', color = 'black') + 
    scale_fill_brewer(palette = 'Pastel1') + 
    theme(axis.text.x = element_text(angle = 60, hjust = 1, size = 10))
}
plot_dodgedbar(cat_train$class_of_worker)
plot_dodgedbar(cat_train$education)
plot_dodgedbar(cat_train$enrolled_in_edu_inst_lastwk)
plot_dodgedbar(cat_train$marital_status)
plot_dodgedbar(cat_train$major_industry_code)
plot_dodgedbar(cat_train$major_occupation_code)

#proportion tables
prop.table(table(cat_train$class_of_worker, cat_train$income_level),1)
prop.table(table(cat_train$marital_status, cat_train$income_level),1)

#DATA CLEANING

#check missing values in numerical data - fortunately, no missing values here
table(is.na(num_train))
table(is.na(num_test))

num_train[, income_level := NULL]

#check for correlation in numerical data
correlatedvars <- findCorrelation(x = cor(num_train), cutoff = 0.7)
correlatedvars

#removing weeks_worked_in_year from both train and test
num_train <-num_train[, -correlatedvars, with = FALSE]
num_test <- num_test[, -correlatedvars, with = FALSE]

#check for missing values proportion in categorical data
missingvaluesprop_train <- sapply(cat_train, function(x){sum(is.na(x))/length(x)})*100 
missingvaluesprop_train

missingvaluesprop_test <- sapply(cat_test, function(x){sum(is.na(x))/length(x)})*100
missingvaluesprop_test

#select only variables which have missing values proportion < 5%
cat_train <- subset(cat_train, select = missingvaluesprop_train < 5)
cat_test <- subset(cat_test, select = missingvaluesprop_test < 5)


#set NA as Unavailable - train data
#convert to characters
cat_train <- cat_train[,names(cat_train) := lapply(.SD, as.character),.SDcols = names(cat_train)]
for (i in seq_along(cat_train)){ 
  set(cat_train, i=which(is.na(cat_train[[i]])), j=i, value="Unavailable")
}
str(cat_train)
#convert back to factors
cat_train <- cat_train[, names(cat_train) := lapply(.SD,factor), .SDcols = names(cat_train)]
str(cat_train)

#set NA as Unavailable - test data
cat_test <- cat_test[, (names(cat_test)) := lapply(.SD, as.character), .SDcols = names(cat_test)]
for (i in seq_along(cat_test)){ 
  set(cat_test, i=which(is.na(cat_test[[i]])), j=i, value="Unavailable")
}
str(cat_test)
#convert back to factors
cat_test <- cat_test[, (names(cat_test)) := lapply(.SD, factor), .SDcols = names(cat_test)]
str(cat_test)

#DATA MANIPULATION

#combine factor levels with less than 5% values because we saw that categorical columns
#have several levels with very low frequencies which can hinder our model performance
#train
for(i in names(cat_train)){
  p <- 5/100
  ld <- names(which(prop.table(table(cat_train[[i]])) < p))
  levels(cat_train[[i]])[levels(cat_train[[i]]) %in% ld] <- "Other"
}

#test
for(i in names(cat_test)){
  p <- 5/100
  ld <- names(which(prop.table(table(cat_test[[i]])) < p))
  levels(cat_test[[i]])[levels(cat_test[[i]]) %in% ld] <- "Other"
}

#check columns with unequal levels - mlr package comes handy

summarizeColumns(cat_train)[, 'nlevs']
summarizeColumns(cat_test)[, 'nlevs']

#Binning numerical variables
num_train[, .N, age][order(age)]
num_train[, .N, wage_per_hour][order(-N)]

num_train[, age := cut(age, breaks = c(0,30,60,90), labels = c("young","adult","old"),
                       include.lowest = TRUE)]

num_test[, age := cut(age, breaks = c(0,30,60,90), labels = c("young","adult","old"),
                       include.lowest = TRUE)]


#Bin numeric variables with Zero and MoreThanZero
num_train[,wage_per_hour := ifelse(wage_per_hour == 0,"Zero","MoreThanZero")][,wage_per_hour := as.factor(wage_per_hour)]
num_train[,capital_gains := ifelse(capital_gains == 0,"Zero","MoreThanZero")][,capital_gains := as.factor(capital_gains)]
num_train[,capital_losses := ifelse(capital_losses == 0,"Zero","MoreThanZero")][,capital_losses := as.factor(capital_losses)]
num_train[,dividend_from_Stocks := ifelse(dividend_from_Stocks == 0,"Zero","MoreThanZero")][,dividend_from_Stocks := as.factor(dividend_from_Stocks)]
            
num_test[,wage_per_hour := ifelse(wage_per_hour == 0,"Zero","MoreThanZero")][,wage_per_hour := as.factor(wage_per_hour)]
num_test[,capital_gains := ifelse(capital_gains == 0,"Zero","MoreThanZero")][,capital_gains := as.factor(capital_gains)]
num_test[,capital_losses := ifelse(capital_losses == 0,"Zero","MoreThanZero")][,capital_losses := as.factor(capital_losses)]
num_test[,dividend_from_Stocks := ifelse(dividend_from_Stocks == 0,"Zero","MoreThanZero")][,dividend_from_Stocks := as.factor(dividend_from_Stocks)]

#MODEL DEVELOPMENT

train <- cbind(num_train, cat_train)
test <- cbind(num_test, cat_test)

#mlr provides nice function makeClassifTask
#can convert train and test to data frames instead of data tables if we want to avoid warnings
train.task <- makeClassifTask(data = train, target = "income_level")
test.task<- makeClassifTask(data = test, target = "income_level")

#remove constant variables with no variance
train.task <- removeConstantFeatures(train.task)
test.task <- removeConstantFeatures(test.task)

#variable importance
# library(rJava)
# library(FSelector)
# 
# var_imp <- generateFilterValuesData(train.task, method = 'information.gain')
# plotFilterValues(var_imp, feat.type.cols = TRUE)

#As our data is highly imbalanced, lets SMOTE it.
#In SMOTE, the algorithm looks at n nearest neighbors, measures the distance between them
#and introduces a new observation at the center of n observations.Its better than undersampling 
#and oversampling
#rate = 10 makes minority class 10 times

system.time(
  train.smote <- smote(train.task,rate = 10,nn = 3) 
)

table(getTaskTargets(train.smote))

#lets see which algorithms are available
listLearners("classif","twoclass")[c("class","package")]


#naive Bayes
naive_learner <- makeLearner("classif.naiveBayes",predict.type = "response")
naive_learner$par.vals <- list(laplace = 1)

#10fold CV - stratified
folds <- makeResampleDesc("CV",iters=10,stratify = TRUE)

#cross validation function
fun_cv <- function(a){
  crv_val <- resample(naive_learner,a,folds,measures = list(acc,tpr,tnr,fpr,fp,fn))
  crv_val$aggr
}

#we can see that smoted data has given better results
fun_cv(train.task)
fun_cv(train.smote)

#train and predict
nB_model <- train(naive_learner, train.smote)
nB_predict <- predict(nB_model,test.task)

#evaluate
nB_prediction <- nB_predict$data$response
dCM <- confusionMatrix(test$income_level,nB_prediction)
dCM
#we can see that it did failed at predicting minority class

#calculate F measure
precision <- dCM$byClass['Pos Pred Value']
recall <- dCM$byClass['Sensitivity']

f_measure <- 2*((precision*recall)/(precision+recall))
f_measure 

#Trying xgboost  
#xgboost
set.seed(2002)
xgb_learner <- makeLearner("classif.xgboost",predict.type = "response")
xgb_learner$par.vals <- list(
  objective = "binary:logistic",
  eval_metric = "error",
  nrounds = 150,
  print.every.n = 50
)

#define hyperparameters for tuning
xg_ps <- makeParamSet( 
  makeIntegerParam("max_depth",lower=3,upper=10),
  makeNumericParam("lambda",lower=0.05,upper=0.5),
  makeNumericParam("eta", lower = 0.01, upper = 0.5),
  makeNumericParam("subsample", lower = 0.50, upper = 1),
  makeNumericParam("min_child_weight",lower=2,upper=10),
  makeNumericParam("colsample_bytree",lower = 0.50,upper = 0.80)
)

#define search function
rancontrol <- makeTuneControlRandom(maxit = 5L) #do 5 iterations

#5 fold cross validation
set_cv <- makeResampleDesc("CV",iters = 5L,stratify = TRUE)

#tune parameters
xgb_tune <- tuneParams(learner = xgb_learner, task = train.task, resampling = set_cv, 
                       measures = list(acc,tpr,tnr,fpr,fp,fn), par.set = xg_ps, 
                       control = rancontrol)

#set optimal parameters
xgb_new <- setHyperPars(learner = xgb_learner, par.vals = xgb_tune$x)

#train model
xgmodel <- train(xgb_new, train.task)

#test model
predict.xg <- predict(xgmodel, test.task)

#make prediction
xg_prediction <- predict.xg$data$response

#make confusion matrix
xg_confused <- confusionMatrix(test$income_level,xg_prediction)

precision <- xg_confused$byClass['Pos Pred Value']
recall <- xg_confused$byClass['Sensitivity']

f_measure <- 2*((precision*recall)/(precision+recall))
f_measure
#0.9726374
#XG Boost outperformed naive bayes


#lets get ROC
#xgboost ROC
xgb_prob <- setPredictType(learner = xgb_new,predict.type = "prob")

#train model
xgmodel_prob <- train(xgb_prob,train.task)

#predict
predict.xgprob <- predict(xgmodel_prob,test.task)

#predicted probabilities
predict.xgprob$data[1:10,]

df <- generateThreshVsPerfData(predict.xgprob,measures = list(fpr,tpr,auc))
plotROCCurves(df)
df
#auc is 0.935871
#to improve the area under curve, we should aim to reduce the threshold so that the 
#false positive rate can be reduced.

#set threshold as 0.4
pred2 <- setThreshold(predict.xgprob,0.4)
confusionMatrix(test$income_level,pred2$data$response)

#With 0.4 threshold, our model returned better predictions than our previous xgboost model at
#0.5 threshold

pred3 <- setThreshold(predict.xgprob,0.30)
confusionMatrix(test$income_level,pred3$data$response)

#This model has outperformed all our models i.e. in other words, this is the best model 
#because 77% of the minority classes have been predicted correctly.


#Lets see if we can improve by experimenting with parameters
#increased no of rounds
#10 fold CV
#increased repetitions in random search

#xgboost
set.seed(2002)
xgb_learner1 <- makeLearner("classif.xgboost",predict.type = "response")
xgb_learner1$par.vals <- list(
  objective = "binary:logistic",
  eval_metric = "error",
  nrounds = 250,
  print.every.n = 50
)

#define hyperparameters for tuning
xg_ps1 <- makeParamSet( 
  makeIntegerParam("max_depth",lower=3,upper=10),
  makeNumericParam("lambda",lower=0.05,upper=0.5),
  makeNumericParam("eta", lower = 0.01, upper = 0.5),
  makeNumericParam("subsample", lower = 0.50, upper = 1),
  makeNumericParam("min_child_weight",lower=2,upper=10),
  makeNumericParam("colsample_bytree",lower = 0.50,upper = 0.80)
)

#define search function
rancontrol1 <- makeTuneControlRandom(maxit = 10L) #do 10 iterations

#10 fold cross validation
set_cv1 <- makeResampleDesc("CV",iters = 10L,stratify = TRUE)

#tune parameters
xgb_tune1 <- tuneParams(learner = xgb_learner1, task = train.task, resampling = set_cv1, 
                       measures = list(acc,tpr,tnr,fpr,fp,fn), par.set = xg_ps1, 
                       control = rancontrol1)

#set optimal parameters
xgb_new1 <- setHyperPars(learner = xgb_learner1, par.vals = xgb_tune1$x)

#train model
xgmodel1 <- train(xgb_new1, train.task)

#test model
predict.xg1 <- predict(xgmodel1, test.task)

#make prediction
xg_prediction1 <- predict.xg1$data$response

#make confusion matrix
xg_confused1 <- confusionMatrix(test$income_level,xg_prediction1)

precision1 <- xg_confused1$byClass['Pos Pred Value']
recall1 <- xg_confused1$byClass['Sensitivity']

f_measure1 <- 2*((precision1*recall1)/(precision1+recall1))
f_measure1
#slightly better performance - 0.9728658

#XG Boost outperformed naive bayes

#lets get ROC
#xgboost ROC
xgb_prob1 <- setPredictType(learner = xgb_new1,predict.type = "prob")

#train model
xgmodel_prob1 <- train(xgb_prob1,train.task)

#predict
predict.xgprob1 <- predict(xgmodel_prob1,test.task)

#predicted probabilities
predict.xgprob1$data[1:10,]

df1 <- generateThreshVsPerfData(predict.xgprob1,measures = list(fpr,tpr,auc))
plotROCCurves(df1)
df1
auc(df1)
#to improve the area under curve, we should aim to reduce the threshold so that the 
#false positive rate can be reduced.

pred4 <- setThreshold(predict.xgprob1,0.30)
confusionMatrix(test$income_level,pred4$data$response)
#slightly better accuracy, sensitivity and specificity


# #SVM - taking forever
# #now lets assign weights to tell the algorithm to pay more attention while classifying minority
# #class
# 
# getParamSet("classif.svm")
# svm_learner <- makeLearner("classif.svm",predict.type = "response")
# #assining more weight to class 1
# svm_learner$par.vals<- list(class.weights = c("0"=1,"1"=10),kernel="radial")
# 
# svm_param <- makeParamSet(
#   makeIntegerParam("cost",lower = 10^-1,upper = 10^2), 
#   makeIntegerParam("gamma",lower= 0.5,upper = 2)
# )
# 
# #random search
# set_search <- makeTuneControlRandom(maxit = 1L) #3 times
# 
# #cross validation #10L seem to take forever
# set_cv <- makeResampleDesc("CV",iters=2L,stratify = TRUE)
# 
# #tune Params
# svm_tune <- tuneParams(learner = svm_learner, task = train.task, measures = 
#             list(acc,tpr,tnr,fpr,fp,fn), par.set = svm_param, control = set_search
#             ,resampling = set_cv)
# 
# 
# #set hyperparameters
# svm_new <- setHyperPars(learner = svm_learner, par.vals = svm_tune$x)
# 
# #train model
# svm_model <- train(svm_new,train.task)
# 
# #test model
# predict_svm <- predict(svm_model,test.task)
# 
# confusionMatrix(d_test$income_level,predict_svm$data$response)
