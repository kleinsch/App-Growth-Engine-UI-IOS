# Introduction

AGE Invitation UI is a drop-in IOS controls that you can deploy to your app within minutes.  AGE Invitation UI will help your users identify and share your app with friends & associates having compatible mobile devices and highest LTV.  For complete feature set and how it works, please visit <a href="http://www.hookmobile.com">Hook Mobile</a>.

# Integration Point

AGE Invitation UI should literally take minutes to integrate because there is only one integration point to your existing app.  You just need to decide when and how to trigger the AGE Invitation UI.  <i>E.g. Do you want to trigger it from a Share button or from an time or conditional event?</i>  

# Getting Sample App Up and Running
A sample app is included with this project that demonstrate AGE Invitation UI launched from a button.  Once you download and open the Xcode project, click on Run button in Xcode.  You may launch the sample app in the simulator or your IOS device.  Running on your iPhone is preferred because you are likely to have more contacts in your iPhone address book to invite from.    

[![](https://dl.dropbox.com/s/izxzj9qxrgl2axd/AGEUI1.PNG)](https://www.dropbox.com/s/izxzj9qxrgl2axd/AGEUI1.PNG)
[![](https://dl.dropbox.com/s/pm1uzrjn1p1dk9v/AGEUI2.PNG)](https://www.dropbox.com/s/pm1uzrjn1p1dk9v/AGEUI2.PNG)

When AGE Invitation UI is invoked for first time, it will analyze the address book.  It may take a few seconds before the list of suggested contacts is displayed.  You may use swipe-pull gesture to force a refresh of the list.  The list of contacts shown in the list is filtered by criteria you define for your app profile in our developer portal.  

Select one or more entries from the suggested and click on the <b>Send</b> button to fire off the invitation text message.  The recipient(s) of the invitation will receive a personalized text message on their phone:

[![](https://dl.dropbox.com/s/zg3qbf5ac8om7cg/inviteSms.PNG)](https://dl.dropbox.com/s/zg3qbf5ac8om7cg/inviteSms.PNG)

The message is completely customizable by you, and it can be further personalized to include the sender and app name.

# Integration Setup
Now that you have a good understanding of the AGE Invitation UI, you are proceed and integrate it into your app.  The first step is to copy all the necessary files into your Xcode project.  AGE Invitation UI requires linking with following system libraries:

* asdf
* asdfs
* asdfss

<li>AddressBook.Framework</li>
<li>MessageUI.Framework</li>
<li>QuartzCore.Framework</li>

AGE Invitation UI depends on following third party open-source libraries.  Source codes for these libraries are included in this project.

<li>MBProgressHUD</li>
<li>ODRefreshControl</li>
<li>OpenUDID</li>