/*
 * Copyright 2015 (c) Mark Liversedge (liversedge@gmail.com)
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the Free
 * Software Foundation; either version 2 of the License, or (at your option)
 * any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
 * more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc., 51
 * Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

#ifndef _GC_APIWebService_h
#define _GC_APIWebService_h

#include <QObject>
#include <QtHttpServer>
#include <QTcpServer>
#include <QDir>
#include <QDate>
#include "RideItem.h"
#include "RideMetadata.h"

struct listRideSettings {
    bool intervals;
    QList<int> wanted; // metrics to list
    QList<FieldDefinition> metafields;
    QList<QString> metawanted; // metadata to list
};

class APIWebService : public QObject
{
    Q_OBJECT

    public:
        explicit APIWebService(QDir home, QObject *parent=nullptr);
        ~APIWebService();

        bool start(quint16 port);
        void stop();



    private:
        QDir home;
        QHttpServer *server;
        QTcpServer *tcpServer = nullptr;

        // route handlers
        QHttpServerResponse handleListAthletes(const QHttpServerRequest &request);
        QHttpServerResponse handleAthleteRequests(const QString &athlete, const QHttpServerRequest &request);
        QHttpServerResponse handleListRides(const QString &athlete, const QHttpServerRequest &request);
        QHttpServerResponse handleListZones(const QString &athlete, const QHttpServerRequest &request);
        QHttpServerResponse handleListMeasures(const QString &athlete, const QString &group, const QHttpServerRequest &request);
        QHttpServerResponse handleListActivity(const QString &athlete, const QString &id, const QHttpServerRequest &request);
        QHttpServerResponse handleListMMP(const QString &athlete, const QString &sub, const QHttpServerRequest &request);
        
        // Helpers
        QHttpServerResponse handleListRidesFast(const QString &athlete, const QDate &since, const QDate &before);
};

#endif
