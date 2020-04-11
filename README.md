# curate-tl

The script was written to curate my own tweets, it *might* be useful for someone else.

It needs [twurl](https://github.com/twitter/twurl), read it's documentation to install and setup it up. Or follow the [tutorial on Twitter](https://developer.twitter.com/en/docs/tutorials/using-twurl).

After having twurl running, copy `demo-conf.yaml` to `conf.yaml` and edit it with our data.

`curate-tl.rb` does the following:

 * Asks if you want to delete your likes
 * Retrieves all the tweets it can, it stores them in `tweets.json`
 * It lists tweets that match the criteria for deletion and asks if you want to proceed. After removing them, it continues with the next batch.


 It accepts the following parameters:

 `-c` It reads the tweets from the local cache (`tweets.json`) instead of retrieving them with the api
 